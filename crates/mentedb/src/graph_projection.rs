//! Renderer-neutral graph projection API for app clients.

use std::collections::HashSet;

use mentedb_core::edge::EdgeType;
use mentedb_core::memory::MemoryType;
use mentedb_core::types::{MemoryId, Timestamp};
use serde::{Deserialize, Serialize};

use crate::{MemoryEdge, MemoryNode, MenteDb, MenteResult};

/// Bounded projection settings for visual graph clients.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphProjectionConfig {
    /// Optional center node. When set, projection walks the graph around it.
    pub center: Option<MemoryId>,
    /// Traversal depth when `center` is set.
    pub depth: usize,
    /// Maximum number of nodes returned to the client.
    pub limit: usize,
    /// Maximum character count for the short node label.
    pub label_chars: usize,
    /// Maximum character count for the longer preview text.
    pub preview_chars: usize,
    /// Include memories and edges that have a `valid_until` timestamp.
    pub include_invalidated: bool,
    /// Include edges between projected nodes.
    pub include_edges: bool,
}

impl Default for GraphProjectionConfig {
    fn default() -> Self {
        Self {
            center: None,
            depth: 2,
            limit: 500,
            label_chars: 64,
            preview_chars: 240,
            include_invalidated: false,
            include_edges: true,
        }
    }
}

/// A bounded graph view that is safe to render on mobile and desktop clients.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphProjection {
    /// Projected memory nodes.
    pub nodes: Vec<GraphProjectionNode>,
    /// Projected edges whose source and target are both present in `nodes`.
    pub edges: Vec<GraphProjectionEdge>,
    /// Number of nodes available before applying the client-facing limit.
    pub available_nodes: usize,
    /// True when the result was capped by `GraphProjectionConfig::limit`.
    pub truncated: bool,
}

/// Node DTO for force-directed, 2D, or 3D graph renderers.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphProjectionNode {
    /// Stable memory identifier.
    pub id: MemoryId,
    /// Compact label suitable for graph node text.
    pub label: String,
    /// Longer preview for hover, search, and side panels.
    pub preview: String,
    /// Memory type classification.
    pub memory_type: MemoryType,
    /// Current salience score.
    pub salience: f32,
    /// Confidence in the memory.
    pub confidence: f32,
    /// Tags copied from the source memory.
    pub tags: Vec<String>,
    /// Creation timestamp in microseconds since epoch.
    pub created_at: Timestamp,
    /// Last access timestamp in microseconds since epoch.
    pub accessed_at: Timestamp,
    /// Optional invalidation timestamp.
    pub valid_until: Option<Timestamp>,
    /// Embedding length without sending the full vector payload.
    pub embedding_dim: usize,
}

/// Edge DTO for graph renderers.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphProjectionEdge {
    /// Source node ID.
    pub source: MemoryId,
    /// Target node ID.
    pub target: MemoryId,
    /// Typed graph relationship.
    pub edge_type: EdgeType,
    /// Relationship strength.
    pub weight: f32,
    /// Optional semantic edge label.
    pub label: Option<String>,
    /// Creation timestamp in microseconds since epoch.
    pub created_at: Timestamp,
    /// Optional invalidation timestamp.
    pub valid_until: Option<Timestamp>,
}

impl MenteDb {
    /// Build a bounded, renderer-neutral graph projection for app clients.
    ///
    /// This method intentionally avoids exposing internal CSR graph structures.
    /// Clients can render the returned DTOs in Flutter, WebGL, desktop UI, or
    /// any other force-directed graph engine.
    pub fn graph_projection(&self, config: GraphProjectionConfig) -> MenteResult<GraphProjection> {
        let (candidate_ids, centered_edges) = match config.center {
            Some(center) => self.graph.get_context_subgraph(center, config.depth),
            None => (self.memory_ids(), Vec::new()),
        };

        let mut nodes = self.load_projection_nodes(&candidate_ids, &config);
        nodes.sort_by(|a, b| {
            b.salience
                .partial_cmp(&a.salience)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| b.created_at.cmp(&a.created_at))
                .then_with(|| a.id.cmp(&b.id))
        });

        let available_nodes = nodes.len();
        let truncated = nodes.len() > config.limit;
        nodes.truncate(config.limit);

        let selected_ids: HashSet<MemoryId> = nodes.iter().map(|node| node.id).collect();
        let edges = if config.include_edges {
            self.load_projection_edges(config.center, &centered_edges, &selected_ids, &config)
        } else {
            Vec::new()
        };

        Ok(GraphProjection {
            nodes,
            edges,
            available_nodes,
            truncated,
        })
    }

    fn load_projection_nodes(
        &self,
        candidate_ids: &[MemoryId],
        config: &GraphProjectionConfig,
    ) -> Vec<GraphProjectionNode> {
        let mut ids = candidate_ids.to_vec();
        ids.sort();
        ids.dedup();

        ids.into_iter()
            .filter_map(|id| self.get_memory(id).ok())
            .filter(|node| config.include_invalidated || !node.is_invalidated())
            .map(|node| projection_node(&node, config))
            .collect()
    }

    fn load_projection_edges(
        &self,
        center: Option<MemoryId>,
        centered_edges: &[MemoryEdge],
        selected_ids: &HashSet<MemoryId>,
        config: &GraphProjectionConfig,
    ) -> Vec<GraphProjectionEdge> {
        let mut edges = match center {
            Some(_) => centered_edges
                .iter()
                .filter(|edge| {
                    selected_ids.contains(&edge.source)
                        && selected_ids.contains(&edge.target)
                        && (config.include_invalidated || !edge.is_invalidated())
                })
                .map(projection_edge)
                .collect(),
            None => {
                let graph = self.graph.read_graph();
                let mut collected = Vec::new();
                let mut source_ids: Vec<MemoryId> = selected_ids.iter().copied().collect();
                source_ids.sort();

                for source in source_ids {
                    for (target, edge) in graph.outgoing(source) {
                        if !selected_ids.contains(&target) {
                            continue;
                        }
                        if !config.include_invalidated && edge.is_invalidated() {
                            continue;
                        }
                        collected.push(GraphProjectionEdge {
                            source,
                            target,
                            edge_type: edge.edge_type,
                            weight: edge.weight,
                            label: edge.label,
                            created_at: edge.created_at,
                            valid_until: edge.valid_until,
                        });
                    }
                }
                collected
            }
        };

        edges.sort_by(|a, b| {
            a.source
                .cmp(&b.source)
                .then_with(|| a.target.cmp(&b.target))
                .then_with(|| a.created_at.cmp(&b.created_at))
        });
        edges.dedup_by(|a, b| {
            a.source == b.source
                && a.target == b.target
                && a.edge_type == b.edge_type
                && a.label == b.label
        });
        edges
    }
}

fn projection_node(node: &MemoryNode, config: &GraphProjectionConfig) -> GraphProjectionNode {
    GraphProjectionNode {
        id: node.id,
        label: first_line_label(&node.content, config.label_chars),
        preview: truncate_chars(&node.content, config.preview_chars),
        memory_type: node.memory_type,
        salience: node.salience,
        confidence: node.confidence,
        tags: node.tags.clone(),
        created_at: node.created_at,
        accessed_at: node.accessed_at,
        valid_until: node.valid_until,
        embedding_dim: node.embedding.len(),
    }
}

fn projection_edge(edge: &MemoryEdge) -> GraphProjectionEdge {
    GraphProjectionEdge {
        source: edge.source,
        target: edge.target,
        edge_type: edge.edge_type,
        weight: edge.weight,
        label: edge.label.clone(),
        created_at: edge.created_at,
        valid_until: edge.valid_until,
    }
}

fn first_line_label(content: &str, max_chars: usize) -> String {
    let first_line = content
        .lines()
        .find(|line| !line.trim().is_empty())
        .unwrap_or(content)
        .trim();
    truncate_chars(first_line, max_chars)
}

fn truncate_chars(content: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }

    let mut truncated = String::new();
    for ch in content.chars().take(max_chars) {
        truncated.push(ch);
    }
    truncated
}
