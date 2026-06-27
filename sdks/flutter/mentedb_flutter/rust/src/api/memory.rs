use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use mentedb::context::DeltaTracker;
use mentedb::prelude::{AgentId, MemoryEdge, MemoryId, MemoryNode};
use mentedb::process_turn::ProcessTurnInput as CoreProcessTurnInput;
use mentedb::{GraphProjectionConfig, MenteDb, SleepMaintenanceConfig};
use mentedb_core::edge::EdgeType;
use mentedb_core::memory::{AttributeValue, MemoryType};
use mentedb_embedding::HashEmbeddingProvider;

/// Request used to open or create a native MenteDB database.
#[derive(Debug, Clone)]
pub struct OpenDatabaseRequest {
    /// Directory where MenteDB stores WAL, pages, indexes, and graph state.
    pub path: String,
    /// Hash embedding dimensionality for local demo recall.
    pub embedding_dimensions: u32,
    /// Optional stable agent identifier. A new one is generated when empty.
    pub agent_id: Option<String>,
}

/// Handle and metadata for an opened native database session.
#[derive(Debug, Clone)]
pub struct OpenDatabaseResult {
    /// Process-local handle used by subsequent bridge calls.
    pub handle: u32,
    /// Canonical database directory used by Rust.
    pub path: String,
    /// Agent ID assigned to memories created through this session.
    pub agent_id: String,
    /// Embedding dimensionality configured for this session.
    pub embedding_dimensions: u32,
    /// Current number of memories visible to the database.
    pub memory_count: u32,
}

/// Memory type accepted by the Flutter bridge.
#[derive(Debug, Clone, Copy)]
pub enum BridgeMemoryType {
    Episodic,
    Semantic,
    Procedural,
    AntiPattern,
    Reasoning,
    Correction,
}

/// Request used to replace or append a text memory bank.
#[derive(Debug, Clone)]
pub struct IngestMemoryBankRequest {
    /// Database handle returned by `open_database`.
    pub handle: u32,
    /// Raw text supplied by the user.
    pub text: String,
    /// Source tag used to replace or filter this memory bank.
    pub source: String,
    /// Classification assigned to every generated memory node.
    pub memory_type: BridgeMemoryType,
    /// Maximum characters per stored memory chunk.
    pub max_chunk_chars: u32,
    /// Remove existing memories tagged with this source before storing chunks.
    pub replace_source: bool,
    /// Flush indexes, graph, and storage after ingest.
    pub flush: bool,
}

/// Summary returned after ingesting a memory bank.
#[derive(Debug, Clone)]
pub struct IngestMemoryBankResult {
    /// Number of chunks stored as memory nodes.
    pub stored: u32,
    /// Number of existing source memories removed before ingest.
    pub replaced: u32,
    /// Number of memories visible after ingest.
    pub memory_count: u32,
    /// Stored memory IDs, encoded as strings for Dart.
    pub memory_ids: Vec<String>,
}

/// Request used to recall memories for a chat prompt.
#[derive(Debug, Clone)]
pub struct RecallMemoryContextRequest {
    /// Database handle returned by `open_database`.
    pub handle: u32,
    /// User question used for hybrid recall.
    pub query: String,
    /// Maximum number of memories to retrieve.
    pub limit: u32,
    /// Maximum characters included in the formatted context string.
    pub max_context_chars: u32,
    /// Optional source tag filter.
    pub source: Option<String>,
}

/// A single recalled memory with score and metadata.
#[derive(Debug, Clone)]
pub struct BridgeRecalledMemory {
    pub id: String,
    pub content: String,
    pub score: f32,
    pub memory_type: BridgeMemoryType,
    pub tags: Vec<String>,
    pub created_at_micros: i64,
    pub salience: f32,
    pub confidence: f32,
}

/// Recall result formatted for immediate LLM prompt injection.
#[derive(Debug, Clone)]
pub struct RecallMemoryContextResult {
    pub context: String,
    pub memories: Vec<BridgeRecalledMemory>,
    pub truncated: bool,
}

/// Request used to persist a completed chat turn as recent episodic memory.
#[derive(Debug, Clone)]
pub struct StoreConversationTurnRequest {
    /// Database handle returned by `open_database`.
    pub handle: u32,
    /// Stable conversation identifier chosen by the app.
    pub conversation_id: String,
    /// Monotonic turn index within the conversation.
    pub turn_index: u32,
    /// User message to persist.
    pub user_message: String,
    /// Assistant message to persist.
    pub assistant_message: String,
    /// Source tag used to retrieve or maintain recent chat separately.
    pub source: String,
    /// Flush indexes, graph, and storage after storing the turn.
    pub flush: bool,
}

/// Summary returned after storing a completed chat turn.
#[derive(Debug, Clone)]
pub struct StoreConversationTurnResult {
    pub stored: u32,
    pub user_memory_id: String,
    pub assistant_memory_id: String,
    pub memory_count: u32,
}

/// Request used to run the full MenteDB conversation pipeline.
#[derive(Debug, Clone)]
pub struct ProcessTurnRequest {
    /// Database handle returned by `open_database`.
    pub handle: u32,
    /// User message for this turn.
    pub user_message: String,
    /// Assistant response when the model has already answered.
    pub assistant_response: Option<String>,
    /// Monotonic turn number chosen by the app.
    pub turn_id: u32,
    /// Optional workspace, chat, or project scope.
    pub project_context: Option<String>,
    /// Optional stable agent identifier. The session agent is used when empty.
    pub agent_id: Option<String>,
    /// Flush indexes, graph, and storage after processing the turn.
    pub flush: bool,
}

/// A scored memory returned by the process_turn retrieval stage.
#[derive(Debug, Clone)]
pub struct ProcessTurnContextItem {
    pub id: String,
    pub content: String,
    pub score: f32,
    pub memory_type: BridgeMemoryType,
    pub tags: Vec<String>,
    pub created_at_micros: i64,
    pub salience: f32,
    pub confidence: f32,
    pub is_new: bool,
    pub from_cache: bool,
    pub scope: String,
}

/// A memory written during a process_turn call.
#[derive(Debug, Clone)]
pub struct ProcessTurnStoredMemory {
    pub id: String,
    pub content: String,
    pub memory_type: BridgeMemoryType,
    pub tags: Vec<String>,
    pub salience: f32,
    pub confidence: f32,
}

/// Pain signal matched during process_turn.
#[derive(Debug, Clone)]
pub struct ProcessTurnPainWarning {
    pub signal_id: String,
    pub intensity: f32,
    pub description: String,
}

/// Action detected from the current turn.
#[derive(Debug, Clone)]
pub struct ProcessTurnDetectedAction {
    pub action_type: String,
    pub detail: String,
}

/// Memory proactively recalled because an action was detected.
#[derive(Debug, Clone)]
pub struct ProcessTurnProactiveRecall {
    pub memory_id: String,
    pub content: String,
    pub relevance: f32,
    pub action_type: String,
}

/// Full Dart DTO for MenteDB's unified process_turn pipeline.
#[derive(Debug, Clone)]
pub struct ProcessTurnResult {
    pub context: Vec<ProcessTurnContextItem>,
    pub context_text: String,
    pub stored: u32,
    pub stored_ids: Vec<String>,
    pub stored_memories: Vec<ProcessTurnStoredMemory>,
    pub episodic_id: Option<String>,
    pub pain_warnings: Vec<ProcessTurnPainWarning>,
    pub cache_hit: bool,
    pub inference_actions: u32,
    pub detected_actions: Vec<ProcessTurnDetectedAction>,
    pub proactive_recalls: Vec<ProcessTurnProactiveRecall>,
    pub correction_id: Option<String>,
    pub sentiment: f32,
    pub phantom_count: u32,
    pub contradiction_count: u32,
    pub predicted_topics: Vec<String>,
    pub facts_extracted: u32,
    pub edges_created: u32,
    pub enrichment_pending: bool,
    pub delta_added: Vec<String>,
    pub delta_removed: Vec<String>,
    pub memory_count: u32,
}

/// Edge type accepted by the Flutter bridge.
#[derive(Debug, Clone, Copy)]
pub enum BridgeEdgeType {
    Caused,
    Before,
    Related,
    Contradicts,
    Supports,
    Supersedes,
    Derived,
    PartOf,
}

/// Request used to project the MenteDB graph for Flutter rendering.
#[derive(Debug, Clone)]
pub struct GraphProjectionRequest {
    pub handle: u32,
    pub center: Option<String>,
    pub depth: u32,
    pub limit: u32,
    pub label_chars: u32,
    pub preview_chars: u32,
    pub include_invalidated: bool,
    pub include_edges: bool,
}

/// Renderer-neutral graph projection returned through FRB.
#[derive(Debug, Clone)]
pub struct BridgeGraphProjection {
    pub nodes: Vec<BridgeGraphProjectionNode>,
    pub edges: Vec<BridgeGraphProjectionEdge>,
    pub available_nodes: u32,
    pub truncated: bool,
}

/// Memory node DTO for Flutter graph renderers.
#[derive(Debug, Clone)]
pub struct BridgeGraphProjectionNode {
    pub id: String,
    pub label: String,
    pub preview: String,
    pub memory_type: BridgeMemoryType,
    pub salience: f32,
    pub confidence: f32,
    pub tags: Vec<String>,
    pub created_at_micros: i64,
    pub accessed_at_micros: i64,
    pub valid_until_micros: Option<i64>,
    pub embedding_dim: u32,
}

/// Graph edge DTO for Flutter graph renderers.
#[derive(Debug, Clone)]
pub struct BridgeGraphProjectionEdge {
    pub source: String,
    pub target: String,
    pub edge_type: BridgeEdgeType,
    pub weight: f32,
    pub label: Option<String>,
    pub created_at_micros: i64,
    pub valid_until_micros: Option<i64>,
}

/// Request used to run bounded sleep maintenance from Flutter background jobs.
#[derive(Debug, Clone)]
pub struct RunSleepMaintenanceRequest {
    pub handle: u32,
    pub max_memories: u32,
    pub apply_decay: bool,
    pub evaluate_archival: bool,
    pub apply_archival_deletes: bool,
    pub run_consolidation: bool,
    pub max_consolidation_clusters: u32,
    pub consolidation_min_cluster_size: u32,
    pub consolidation_similarity_threshold: f32,
    pub link_entities: bool,
}

/// Non-fatal issue reported by a sleep maintenance stage.
#[derive(Debug, Clone)]
pub struct BridgeSleepMaintenanceIssue {
    pub stage: String,
    pub memory_id: Option<String>,
    pub message: String,
}

/// Summary of a leased sleep maintenance run.
#[derive(Debug, Clone)]
pub struct BridgeSleepMaintenanceResult {
    pub lease_acquired: bool,
    pub processed_memories: u32,
    pub decay_updated: u32,
    pub archival_evaluated: u32,
    pub archival_keep: u32,
    pub archival_archive: u32,
    pub archival_delete: u32,
    pub archival_consolidate: u32,
    pub archival_delete_applied: u32,
    pub consolidation_candidates: u32,
    pub consolidated: u32,
    pub consolidated_memory_ids: Vec<String>,
    pub entity_pairs_linked: u32,
    pub entity_edges_created: u32,
    pub entity_pairs_ambiguous: u32,
    pub enrichment_pending: bool,
    pub enrichment_candidates: u32,
    pub issues: Vec<BridgeSleepMaintenanceIssue>,
}

/// Initialize FRB user utilities.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Open or create a MenteDB database and return a process-local session handle.
pub fn open_database(request: OpenDatabaseRequest) -> Result<OpenDatabaseResult> {
    let path = normalize_database_path(&request.path)?;
    let embedding_dimensions = validate_positive_u32(
        request.embedding_dimensions,
        "embedding_dimensions must be greater than zero",
    )?;
    let agent_id = parse_agent_id(request.agent_id.as_deref())?;

    std::fs::create_dir_all(&path)
        .with_context(|| format!("failed to create database directory {}", path.display()))?;
    let embedder = Box::new(HashEmbeddingProvider::new(embedding_dimensions as usize));
    let db = MenteDb::open_with_embedder(&path, embedder)
        .with_context(|| format!("failed to open MenteDB at {}", path.display()))?;
    let memory_count = to_u32(db.memory_count(), "memory_count")?;

    let session = Arc::new(DbSession {
        db: Mutex::new(db),
        delta_tracker: Mutex::new(DeltaTracker::new()),
        path: path.clone(),
        agent_id,
        embedding_dimensions,
    });

    let handle = registry()
        .lock()
        .map_err(|_| anyhow!("session registry lock was poisoned"))?
        .insert(session)?;

    Ok(OpenDatabaseResult {
        handle,
        path: path.to_string_lossy().to_string(),
        agent_id: agent_id.to_string(),
        embedding_dimensions,
        memory_count,
    })
}

/// Close a MenteDB session and flush persisted state.
pub fn close_database(handle: u32) -> Result<()> {
    let session = registry()
        .lock()
        .map_err(|_| anyhow!("session registry lock was poisoned"))?
        .remove(handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;
    db.close()
        .with_context(|| format!("failed to close MenteDB at {}", session.path.display()))?;
    Ok(())
}

/// Flush a MenteDB session without closing it.
pub fn flush_database(handle: u32) -> Result<()> {
    let session = get_session(handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;
    db.flush()
        .with_context(|| format!("failed to flush MenteDB at {}", session.path.display()))?;
    Ok(())
}

/// Return the number of memories visible through a session.
pub fn memory_count(handle: u32) -> Result<u32> {
    let session = get_session(handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;
    to_u32(db.memory_count(), "memory_count")
}

/// Store user text as real MenteDB memory nodes.
pub fn ingest_memory_bank(request: IngestMemoryBankRequest) -> Result<IngestMemoryBankResult> {
    let source = normalize_source(&request.source)?;
    let max_chunk_chars = validate_positive_u32(
        request.max_chunk_chars,
        "max_chunk_chars must be greater than zero",
    )? as usize;
    let chunks = chunk_memory_bank(&request.text, max_chunk_chars)?;
    let session = get_session(request.handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;

    let replaced = if request.replace_source {
        clear_source_memories(&db, &source)?
    } else {
        0
    };

    let mut nodes = Vec::with_capacity(chunks.len());
    for (index, chunk) in chunks.iter().enumerate() {
        let embedding = db
            .embed_text(chunk)?
            .ok_or_else(|| anyhow!("database session has no embedding provider"))?;
        let mut node = MemoryNode::new(
            session.agent_id,
            request.memory_type.into(),
            chunk.clone(),
            embedding,
        );
        node.tags.push("flutter_memory_bank".to_string());
        node.tags.push(source.clone());
        node.attributes
            .insert("source".to_string(), AttributeValue::String(source.clone()));
        node.attributes.insert(
            "chunk_index".to_string(),
            AttributeValue::Integer(to_i64(index, "chunk_index")?),
        );
        node.attributes.insert(
            "embedding_provider".to_string(),
            AttributeValue::String(format!("hash-embedding-{}d", session.embedding_dimensions)),
        );
        nodes.push(node);
    }

    let ids = db
        .store_batch(nodes)
        .context("failed to store memory bank")?;
    if request.flush {
        db.flush().context("failed to flush memory bank ingest")?;
    }

    Ok(IngestMemoryBankResult {
        stored: to_u32(ids.len(), "stored")?,
        replaced: to_u32(replaced, "replaced")?,
        memory_count: to_u32(db.memory_count(), "memory_count")?,
        memory_ids: ids.iter().map(ToString::to_string).collect(),
    })
}

/// Recall a bounded MenteDB context for a chat prompt.
pub fn recall_memory_context(
    request: RecallMemoryContextRequest,
) -> Result<RecallMemoryContextResult> {
    let limit = validate_positive_u32(request.limit, "limit must be greater than zero")? as usize;
    let max_context_chars = validate_positive_u32(
        request.max_context_chars,
        "max_context_chars must be greater than zero",
    )? as usize;
    let query = request.query.trim();
    if query.is_empty() {
        bail!("query must not be empty");
    }
    let source = match request.source {
        Some(value) if !value.trim().is_empty() => Some(normalize_source(&value)?),
        _ => None,
    };

    let session = get_session(request.handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;
    let embedding = db
        .embed_text(query)?
        .ok_or_else(|| anyhow!("database session has no embedding provider"))?;
    let tag_values: Vec<&str> = source.iter().map(String::as_str).collect();
    let tags = if tag_values.is_empty() {
        None
    } else {
        Some(tag_values.as_slice())
    };

    let results = db
        .recall_hybrid_at(
            &embedding,
            Some(query),
            limit,
            current_timestamp_micros(),
            tags,
            None,
        )
        .context("failed to recall memories")?;

    let mut memories = Vec::with_capacity(results.len());
    for (id, score) in results {
        let node = db
            .get_memory(id)
            .with_context(|| format!("failed to load recalled memory {id}"))?;
        memories.push(BridgeRecalledMemory {
            id: id.to_string(),
            content: node.content,
            score,
            memory_type: node.memory_type.into(),
            tags: node.tags,
            created_at_micros: to_i64_u64(node.created_at, "created_at_micros")?,
            salience: node.salience,
            confidence: node.confidence,
        });
    }

    let (context, truncated) = format_context(&memories, max_context_chars);
    Ok(RecallMemoryContextResult {
        context,
        memories,
        truncated,
    })
}

/// Store a completed user and assistant exchange as recent episodic memory.
pub fn store_conversation_turn(
    request: StoreConversationTurnRequest,
) -> Result<StoreConversationTurnResult> {
    let conversation_id = normalize_source(&request.conversation_id)?;
    let source = normalize_source(&request.source)?;
    let user_message = normalize_message(&request.user_message, "user_message")?;
    let assistant_message = normalize_message(&request.assistant_message, "assistant_message")?;
    let session = get_session(request.handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;

    let mut user_node = build_embedded_memory(
        &db,
        session.agent_id,
        MemoryType::Episodic,
        format!("User: {user_message}"),
    )?;
    add_conversation_metadata(
        &mut user_node,
        &source,
        &conversation_id,
        request.turn_index,
        "user",
    );

    let mut assistant_node = build_embedded_memory(
        &db,
        session.agent_id,
        MemoryType::Episodic,
        format!("Assistant: {assistant_message}"),
    )?;
    add_conversation_metadata(
        &mut assistant_node,
        &source,
        &conversation_id,
        request.turn_index,
        "assistant",
    );

    let user_memory_id = user_node.id;
    let assistant_memory_id = assistant_node.id;
    db.store_batch(vec![user_node, assistant_node])
        .context("failed to store conversation turn")?;

    let now = current_timestamp_micros();
    db.relate(MemoryEdge {
        source: user_memory_id,
        target: assistant_memory_id,
        edge_type: EdgeType::Before,
        weight: 1.0,
        created_at: now,
        valid_from: None,
        valid_until: None,
        label: Some("assistant_response".to_string()),
    })
    .context("failed to relate conversation turn")?;

    if request.flush {
        db.flush().context("failed to flush conversation turn")?;
    }

    Ok(StoreConversationTurnResult {
        stored: 2,
        user_memory_id: user_memory_id.to_string(),
        assistant_memory_id: assistant_memory_id.to_string(),
        memory_count: to_u32(db.memory_count(), "memory_count")?,
    })
}

/// Process a conversation turn through MenteDB's unified cognitive pipeline.
pub fn process_turn(request: ProcessTurnRequest) -> Result<ProcessTurnResult> {
    let user_message = normalize_message(&request.user_message, "user_message")?;
    let assistant_response = request
        .assistant_response
        .map(|value| normalize_message(&value, "assistant_response"))
        .transpose()?;
    let project_context = match request.project_context {
        Some(value) if !value.trim().is_empty() => Some(normalize_source(&value)?),
        _ => None,
    };

    let session = get_session(request.handle)?;
    let agent_id = match request.agent_id {
        Some(value) if !value.trim().is_empty() => Some(parse_agent_id(Some(&value))?.0),
        _ => Some(session.agent_id.0),
    };
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;
    let mut delta_tracker = session
        .delta_tracker
        .lock()
        .map_err(|_| anyhow!("delta tracker lock was poisoned"))?;

    let input = CoreProcessTurnInput {
        user_message,
        assistant_response,
        turn_id: u64::from(request.turn_id),
        project_context,
        agent_id,
    };
    let result = db
        .process_turn(&input, &mut delta_tracker)
        .context("failed to process conversation turn")?;

    if request.flush {
        db.flush().context("failed to flush processed turn")?;
    }

    bridge_process_turn_result(&db, result)
}

/// Build a bounded graph projection from the native MenteDB graph.
pub fn graph_projection(request: GraphProjectionRequest) -> Result<BridgeGraphProjection> {
    let center = match request.center {
        Some(value) if !value.trim().is_empty() => {
            Some(MemoryId::from_str(value.trim()).context("invalid graph center memory id")?)
        }
        _ => None,
    };
    let config = GraphProjectionConfig {
        center,
        depth: validate_positive_u32(request.depth, "depth must be greater than zero")? as usize,
        limit: validate_positive_u32(request.limit, "limit must be greater than zero")? as usize,
        label_chars: validate_positive_u32(
            request.label_chars,
            "label_chars must be greater than zero",
        )? as usize,
        preview_chars: validate_positive_u32(
            request.preview_chars,
            "preview_chars must be greater than zero",
        )? as usize,
        include_invalidated: request.include_invalidated,
        include_edges: request.include_edges,
    };

    let session = get_session(request.handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;
    let projection = db
        .graph_projection(config)
        .context("failed to build graph projection")?;

    Ok(BridgeGraphProjection {
        nodes: projection
            .nodes
            .into_iter()
            .map(|node| {
                Ok(BridgeGraphProjectionNode {
                    id: node.id.to_string(),
                    label: node.label,
                    preview: node.preview,
                    memory_type: node.memory_type.into(),
                    salience: node.salience,
                    confidence: node.confidence,
                    tags: node.tags,
                    created_at_micros: to_i64_u64(node.created_at, "created_at_micros")?,
                    accessed_at_micros: to_i64_u64(node.accessed_at, "accessed_at_micros")?,
                    valid_until_micros: node
                        .valid_until
                        .map(|value| to_i64_u64(value, "valid_until_micros"))
                        .transpose()?,
                    embedding_dim: to_u32(node.embedding_dim, "embedding_dim")?,
                })
            })
            .collect::<Result<Vec<_>>>()?,
        edges: projection
            .edges
            .into_iter()
            .map(|edge| {
                Ok(BridgeGraphProjectionEdge {
                    source: edge.source.to_string(),
                    target: edge.target.to_string(),
                    edge_type: edge.edge_type.into(),
                    weight: edge.weight,
                    label: edge.label,
                    created_at_micros: to_i64_u64(edge.created_at, "edge_created_at_micros")?,
                    valid_until_micros: edge
                        .valid_until
                        .map(|value| to_i64_u64(value, "edge_valid_until_micros"))
                        .transpose()?,
                })
            })
            .collect::<Result<Vec<_>>>()?,
        available_nodes: to_u32(projection.available_nodes, "available_nodes")?,
        truncated: projection.truncated,
    })
}

/// Run MenteDB sleep maintenance under the database lease.
pub fn run_sleep_maintenance(
    request: RunSleepMaintenanceRequest,
) -> Result<BridgeSleepMaintenanceResult> {
    let session = get_session(request.handle)?;
    let db = session
        .db
        .lock()
        .map_err(|_| anyhow!("database session lock was poisoned"))?;
    let config = SleepMaintenanceConfig {
        max_memories: validate_positive_u32(
            request.max_memories,
            "max_memories must be greater than zero",
        )? as usize,
        apply_decay: request.apply_decay,
        evaluate_archival: request.evaluate_archival,
        apply_archival_deletes: request.apply_archival_deletes,
        run_consolidation: request.run_consolidation,
        max_consolidation_clusters: validate_positive_u32(
            request.max_consolidation_clusters,
            "max_consolidation_clusters must be greater than zero",
        )? as usize,
        consolidation_min_cluster_size: validate_positive_u32(
            request.consolidation_min_cluster_size,
            "consolidation_min_cluster_size must be greater than zero",
        )? as usize,
        consolidation_similarity_threshold: request.consolidation_similarity_threshold,
        link_entities: request.link_entities,
        ..SleepMaintenanceConfig::default()
    };

    let Some(result) = db
        .try_run_sleep_maintenance(config)
        .context("failed to run sleep maintenance")?
    else {
        return Ok(BridgeSleepMaintenanceResult::lease_busy());
    };

    BridgeSleepMaintenanceResult::from_core(result, true)
}

fn get_session(handle: u32) -> Result<Arc<DbSession>> {
    registry()
        .lock()
        .map_err(|_| anyhow!("session registry lock was poisoned"))?
        .get(handle)
}

fn registry() -> &'static Mutex<SessionRegistry> {
    static REGISTRY: OnceLock<Mutex<SessionRegistry>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(SessionRegistry::default()))
}

#[flutter_rust_bridge::frb(ignore)]
struct DbSession {
    db: Mutex<MenteDb>,
    delta_tracker: Mutex<DeltaTracker>,
    path: PathBuf,
    agent_id: AgentId,
    embedding_dimensions: u32,
}

#[flutter_rust_bridge::frb(ignore)]
struct SessionRegistry {
    next_handle: u32,
    sessions: HashMap<u32, Arc<DbSession>>,
}

impl Default for SessionRegistry {
    fn default() -> Self {
        Self {
            next_handle: 1,
            sessions: HashMap::new(),
        }
    }
}

impl SessionRegistry {
    fn insert(&mut self, session: Arc<DbSession>) -> Result<u32> {
        let handle = self.next_handle;
        self.next_handle = self
            .next_handle
            .checked_add(1)
            .ok_or_else(|| anyhow!("database handle space exhausted"))?;
        self.sessions.insert(handle, session);
        Ok(handle)
    }

    fn get(&self, handle: u32) -> Result<Arc<DbSession>> {
        self.sessions
            .get(&handle)
            .cloned()
            .ok_or_else(|| anyhow!("unknown database handle {handle}"))
    }

    fn remove(&mut self, handle: u32) -> Result<Arc<DbSession>> {
        self.sessions
            .remove(&handle)
            .ok_or_else(|| anyhow!("unknown database handle {handle}"))
    }
}

impl From<BridgeMemoryType> for MemoryType {
    fn from(value: BridgeMemoryType) -> Self {
        match value {
            BridgeMemoryType::Episodic => MemoryType::Episodic,
            BridgeMemoryType::Semantic => MemoryType::Semantic,
            BridgeMemoryType::Procedural => MemoryType::Procedural,
            BridgeMemoryType::AntiPattern => MemoryType::AntiPattern,
            BridgeMemoryType::Reasoning => MemoryType::Reasoning,
            BridgeMemoryType::Correction => MemoryType::Correction,
        }
    }
}

impl From<MemoryType> for BridgeMemoryType {
    fn from(value: MemoryType) -> Self {
        match value {
            MemoryType::Episodic => BridgeMemoryType::Episodic,
            MemoryType::Semantic => BridgeMemoryType::Semantic,
            MemoryType::Procedural => BridgeMemoryType::Procedural,
            MemoryType::AntiPattern => BridgeMemoryType::AntiPattern,
            MemoryType::Reasoning => BridgeMemoryType::Reasoning,
            MemoryType::Correction => BridgeMemoryType::Correction,
        }
    }
}

impl From<EdgeType> for BridgeEdgeType {
    fn from(value: EdgeType) -> Self {
        match value {
            EdgeType::Caused => BridgeEdgeType::Caused,
            EdgeType::Before => BridgeEdgeType::Before,
            EdgeType::Related => BridgeEdgeType::Related,
            EdgeType::Contradicts => BridgeEdgeType::Contradicts,
            EdgeType::Supports => BridgeEdgeType::Supports,
            EdgeType::Supersedes => BridgeEdgeType::Supersedes,
            EdgeType::Derived => BridgeEdgeType::Derived,
            EdgeType::PartOf => BridgeEdgeType::PartOf,
        }
    }
}

fn bridge_process_turn_result(
    db: &MenteDb,
    value: mentedb::process_turn::ProcessTurnResult,
) -> Result<ProcessTurnResult> {
    let delta_added_ids: HashSet<MemoryId> = value.delta_added.iter().copied().collect();
    let context = value
        .context
        .iter()
        .map(|scored| bridge_context_item(scored, &delta_added_ids, value.cache_hit))
        .collect::<Result<Vec<_>>>()?;
    let stored_memories = value
        .stored_ids
        .iter()
        .map(|id| bridge_stored_memory(db, *id))
        .collect::<Result<Vec<_>>>()?;
    let stored_ids = value
        .stored_ids
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    let context_text = format_process_turn_context(&context);

    Ok(ProcessTurnResult {
        context,
        context_text,
        stored: to_u32(stored_ids.len(), "stored")?,
        stored_ids,
        stored_memories,
        episodic_id: value.episodic_id.map(|id| id.to_string()),
        pain_warnings: value
            .pain_warnings
            .into_iter()
            .map(|warning| ProcessTurnPainWarning {
                signal_id: warning.signal_id.to_string(),
                intensity: warning.intensity,
                description: warning.description,
            })
            .collect(),
        cache_hit: value.cache_hit,
        inference_actions: value.inference_actions,
        detected_actions: value
            .detected_actions
            .into_iter()
            .map(|action| ProcessTurnDetectedAction {
                action_type: action.action_type,
                detail: action.detail,
            })
            .collect(),
        proactive_recalls: value
            .proactive_recalls
            .into_iter()
            .map(|recall| ProcessTurnProactiveRecall {
                memory_id: recall.memory_id.to_string(),
                content: recall.content,
                relevance: recall.relevance,
                action_type: recall.action_type,
            })
            .collect(),
        correction_id: value.correction_id.map(|id| id.to_string()),
        sentiment: value.sentiment,
        phantom_count: to_u32(value.phantom_count, "phantom_count")?,
        contradiction_count: to_u32(value.contradiction_count, "contradiction_count")?,
        predicted_topics: value.predicted_topics,
        facts_extracted: to_u32(value.facts_extracted, "facts_extracted")?,
        edges_created: value.edges_created,
        enrichment_pending: value.enrichment_pending,
        delta_added: value.delta_added.iter().map(ToString::to_string).collect(),
        delta_removed: value
            .delta_removed
            .iter()
            .map(ToString::to_string)
            .collect(),
        memory_count: to_u32(db.memory_count(), "memory_count")?,
    })
}

fn bridge_context_item(
    scored: &mentedb::context::ScoredMemory,
    delta_added_ids: &HashSet<MemoryId>,
    cache_hit: bool,
) -> Result<ProcessTurnContextItem> {
    let memory = &scored.memory;
    Ok(ProcessTurnContextItem {
        id: memory.id.to_string(),
        content: memory.content.clone(),
        score: scored.score,
        memory_type: memory.memory_type.into(),
        tags: memory.tags.clone(),
        created_at_micros: to_i64_u64(memory.created_at, "context_created_at_micros")?,
        salience: memory.salience,
        confidence: memory.confidence,
        is_new: delta_added_ids.contains(&memory.id),
        from_cache: cache_hit,
        scope: infer_memory_scope(&memory.tags),
    })
}

fn bridge_stored_memory(db: &MenteDb, id: MemoryId) -> Result<ProcessTurnStoredMemory> {
    let memory = db
        .get_memory(id)
        .with_context(|| format!("failed to load stored memory {id}"))?;
    Ok(ProcessTurnStoredMemory {
        id: memory.id.to_string(),
        content: memory.content,
        memory_type: memory.memory_type.into(),
        tags: memory.tags,
        salience: memory.salience,
        confidence: memory.confidence,
    })
}

fn infer_memory_scope(tags: &[String]) -> String {
    if tags.iter().any(|tag| tag == "scope:always") {
        return "always".to_string();
    }
    if tags.iter().any(|tag| tag.starts_with("scope:project:")) {
        return "project".to_string();
    }
    "contextual".to_string()
}

fn format_process_turn_context(memories: &[ProcessTurnContextItem]) -> String {
    let mut context = String::new();
    for (index, memory) in memories.iter().enumerate() {
        let cleaned = memory.content.replace('\n', " ");
        let line = format!(
            "{}. [{}] {} (score {:.3}, scope {})\n",
            index + 1,
            bridge_memory_type_label(memory.memory_type),
            cleaned,
            memory.score,
            memory.scope
        );
        context.push_str(&line);
    }
    context.trim().to_string()
}

fn bridge_memory_type_label(memory_type: BridgeMemoryType) -> &'static str {
    match memory_type {
        BridgeMemoryType::Episodic => "episodic",
        BridgeMemoryType::Semantic => "semantic",
        BridgeMemoryType::Procedural => "procedural",
        BridgeMemoryType::AntiPattern => "anti_pattern",
        BridgeMemoryType::Reasoning => "reasoning",
        BridgeMemoryType::Correction => "correction",
    }
}

impl BridgeSleepMaintenanceResult {
    fn lease_busy() -> Self {
        Self {
            lease_acquired: false,
            processed_memories: 0,
            decay_updated: 0,
            archival_evaluated: 0,
            archival_keep: 0,
            archival_archive: 0,
            archival_delete: 0,
            archival_consolidate: 0,
            archival_delete_applied: 0,
            consolidation_candidates: 0,
            consolidated: 0,
            consolidated_memory_ids: Vec::new(),
            entity_pairs_linked: 0,
            entity_edges_created: 0,
            entity_pairs_ambiguous: 0,
            enrichment_pending: false,
            enrichment_candidates: 0,
            issues: Vec::new(),
        }
    }

    fn from_core(value: mentedb::SleepMaintenanceResult, lease_acquired: bool) -> Result<Self> {
        Ok(Self {
            lease_acquired,
            processed_memories: to_u32(value.processed_memories, "processed_memories")?,
            decay_updated: to_u32(value.decay_updated, "decay_updated")?,
            archival_evaluated: to_u32(value.archival_evaluated, "archival_evaluated")?,
            archival_keep: to_u32(value.archival_keep, "archival_keep")?,
            archival_archive: to_u32(value.archival_archive, "archival_archive")?,
            archival_delete: to_u32(value.archival_delete, "archival_delete")?,
            archival_consolidate: to_u32(value.archival_consolidate, "archival_consolidate")?,
            archival_delete_applied: to_u32(
                value.archival_delete_applied,
                "archival_delete_applied",
            )?,
            consolidation_candidates: to_u32(
                value.consolidation_candidates,
                "consolidation_candidates",
            )?,
            consolidated: to_u32(value.consolidated, "consolidated")?,
            consolidated_memory_ids: value
                .consolidated_memory_ids
                .iter()
                .map(ToString::to_string)
                .collect(),
            entity_pairs_linked: to_u32(value.entity_pairs_linked, "entity_pairs_linked")?,
            entity_edges_created: to_u32(value.entity_edges_created, "entity_edges_created")?,
            entity_pairs_ambiguous: to_u32(value.entity_pairs_ambiguous, "entity_pairs_ambiguous")?,
            enrichment_pending: value.enrichment_pending,
            enrichment_candidates: to_u32(value.enrichment_candidates, "enrichment_candidates")?,
            issues: value
                .issues
                .into_iter()
                .map(|issue| BridgeSleepMaintenanceIssue {
                    stage: format!("{:?}", issue.stage),
                    memory_id: issue.memory_id.map(|id| id.to_string()),
                    message: issue.message,
                })
                .collect(),
        })
    }
}

fn clear_source_memories(db: &MenteDb, source: &str) -> Result<usize> {
    let ids: Vec<MemoryId> = db
        .memory_ids()
        .into_iter()
        .filter(|id| {
            db.get_memory(*id)
                .map(|node| node.tags.iter().any(|tag| tag == source))
                .unwrap_or(false)
        })
        .collect();

    for id in &ids {
        db.forget(*id)
            .with_context(|| format!("failed to replace memory {id}"))?;
    }
    Ok(ids.len())
}

fn build_embedded_memory(
    db: &MenteDb,
    agent_id: AgentId,
    memory_type: MemoryType,
    content: String,
) -> Result<MemoryNode> {
    let embedding = db
        .embed_text(&content)?
        .ok_or_else(|| anyhow!("database session has no embedding provider"))?;
    Ok(MemoryNode::new(agent_id, memory_type, content, embedding))
}

fn add_conversation_metadata(
    node: &mut MemoryNode,
    source: &str,
    conversation_id: &str,
    turn_index: u32,
    role: &str,
) {
    node.tags.push("recent_chat".to_string());
    node.tags.push(source.to_string());
    node.tags.push(format!("conversation:{conversation_id}"));
    node.tags.push(format!("role:{role}"));
    node.attributes.insert(
        "source".to_string(),
        AttributeValue::String(source.to_string()),
    );
    node.attributes.insert(
        "conversation_id".to_string(),
        AttributeValue::String(conversation_id.to_string()),
    );
    node.attributes.insert(
        "turn_index".to_string(),
        AttributeValue::Integer(i64::from(turn_index)),
    );
    node.attributes
        .insert("role".to_string(), AttributeValue::String(role.to_string()));
}

fn chunk_memory_bank(text: &str, max_chunk_chars: usize) -> Result<Vec<String>> {
    let mut chunks = Vec::new();
    let mut current = String::new();

    for line in text.lines().map(str::trim).filter(|line| !line.is_empty()) {
        append_chunk_line(&mut chunks, &mut current, line, max_chunk_chars);
    }

    if !current.trim().is_empty() {
        chunks.push(current.trim().to_string());
    }

    if chunks.is_empty() {
        bail!("memory text must contain at least one non-empty line");
    }

    Ok(chunks)
}

fn append_chunk_line(
    chunks: &mut Vec<String>,
    current: &mut String,
    line: &str,
    max_chunk_chars: usize,
) {
    if line.chars().count() > max_chunk_chars {
        if !current.trim().is_empty() {
            chunks.push(current.trim().to_string());
            current.clear();
        }
        split_long_line(line, max_chunk_chars, chunks);
        return;
    }

    let separator_len = usize::from(!current.is_empty());
    if current.chars().count() + separator_len + line.chars().count() > max_chunk_chars
        && !current.is_empty()
    {
        chunks.push(current.trim().to_string());
        current.clear();
    }

    if !current.is_empty() {
        current.push('\n');
    }
    current.push_str(line);
}

fn split_long_line(line: &str, max_chunk_chars: usize, chunks: &mut Vec<String>) {
    let mut current = String::new();
    for ch in line.chars() {
        if current.chars().count() >= max_chunk_chars {
            chunks.push(current);
            current = String::new();
        }
        current.push(ch);
    }
    if !current.is_empty() {
        chunks.push(current);
    }
}

fn format_context(memories: &[BridgeRecalledMemory], max_context_chars: usize) -> (String, bool) {
    let mut context = String::new();
    let mut truncated = false;

    for (index, memory) in memories.iter().enumerate() {
        let cleaned = memory.content.replace('\n', " ");
        let line = format!("{}. {} (score {:.3})\n", index + 1, cleaned, memory.score);
        if context.chars().count() + line.chars().count() > max_context_chars {
            truncated = true;
            if context.is_empty() {
                context = line.chars().take(max_context_chars).collect();
            }
            break;
        }
        context.push_str(&line);
    }

    (context.trim().to_string(), truncated)
}

fn normalize_database_path(path: &str) -> Result<PathBuf> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        bail!("database path must not be empty");
    }
    Ok(Path::new(trimmed).to_path_buf())
}

fn normalize_source(source: &str) -> Result<String> {
    let trimmed = source.trim();
    if trimmed.is_empty() {
        bail!("source must not be empty");
    }
    Ok(trimmed.to_string())
}

fn normalize_message(message: &str, field: &str) -> Result<String> {
    let trimmed = message.trim();
    if trimmed.is_empty() {
        bail!("{field} must not be empty");
    }
    Ok(trimmed.to_string())
}

fn parse_agent_id(agent_id: Option<&str>) -> Result<AgentId> {
    match agent_id.map(str::trim).filter(|value| !value.is_empty()) {
        Some(value) => {
            AgentId::from_str(value).with_context(|| format!("invalid agent_id {value}"))
        }
        None => Ok(AgentId::new()),
    }
}

fn validate_positive_u32(value: u32, message: &str) -> Result<u32> {
    if value == 0 {
        bail!("{message}");
    }
    Ok(value)
}

fn current_timestamp_micros() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_micros().min(u128::from(u64::MAX)) as u64)
        .unwrap_or_default()
}

fn to_u32(value: usize, field: &str) -> Result<u32> {
    u32::try_from(value).with_context(|| format!("{field} exceeded u32 range"))
}

fn to_i64(value: usize, field: &str) -> Result<i64> {
    i64::try_from(value).with_context(|| format!("{field} exceeded i64 range"))
}

fn to_i64_u64(value: u64, field: &str) -> Result<i64> {
    i64::try_from(value).with_context(|| format!("{field} exceeded i64 range"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bridge_ingests_recalls_and_runs_sleep_maintenance() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        let opened = open_database(OpenDatabaseRequest {
            path: temp_dir.path().join("memory").to_string_lossy().to_string(),
            embedding_dimensions: 64,
            agent_id: None,
        })
        .expect("open database");

        let ingest = ingest_memory_bank(IngestMemoryBankRequest {
            handle: opened.handle,
            text: "Alex avoids peanuts.\nAlex likes mushrooms.".to_string(),
            source: "test_bank".to_string(),
            memory_type: BridgeMemoryType::Semantic,
            max_chunk_chars: 120,
            replace_source: true,
            flush: true,
        })
        .expect("ingest memory bank");
        assert_eq!(ingest.stored, 1);
        assert_eq!(ingest.memory_count, 1);

        let recall = recall_memory_context(RecallMemoryContextRequest {
            handle: opened.handle,
            query: "What should I avoid for Alex?".to_string(),
            limit: 4,
            max_context_chars: 512,
            source: Some("test_bank".to_string()),
        })
        .expect("recall memory context");
        assert!(!recall.context.is_empty());
        assert_eq!(recall.memories.len(), 1);

        let turn = store_conversation_turn(StoreConversationTurnRequest {
            handle: opened.handle,
            conversation_id: "test_conversation".to_string(),
            turn_index: 1,
            user_message: "What should I cook for Alex?".to_string(),
            assistant_message: "Avoid peanuts and consider mushrooms.".to_string(),
            source: "recent_chat".to_string(),
            flush: true,
        })
        .expect("store conversation turn");
        assert_eq!(turn.stored, 2);
        assert_eq!(turn.memory_count, 3);

        let processed = process_turn(ProcessTurnRequest {
            handle: opened.handle,
            user_message: "Deploy a vegetarian dinner plan without peanut sauce.".to_string(),
            assistant_response: Some("Use mushrooms and keep nut sauces out.".to_string()),
            turn_id: 2,
            project_context: Some("test_project".to_string()),
            agent_id: None,
            flush: true,
        })
        .expect("process turn");
        assert_eq!(processed.stored, 1);
        assert!(processed.episodic_id.is_some());
        assert!(!processed.context_text.is_empty());
        assert!(
            processed
                .detected_actions
                .iter()
                .any(|action| action.action_type == "deployment")
        );

        let graph = graph_projection(GraphProjectionRequest {
            handle: opened.handle,
            center: None,
            depth: 2,
            limit: 25,
            label_chars: 64,
            preview_chars: 180,
            include_invalidated: false,
            include_edges: true,
        })
        .expect("graph projection");
        assert!(graph.nodes.len() >= 4);
        assert!(
            graph
                .edges
                .iter()
                .any(|edge| edge.source == turn.user_memory_id
                    && edge.target == turn.assistant_memory_id
                    && matches!(edge.edge_type, BridgeEdgeType::Before))
        );

        let sleep = run_sleep_maintenance(RunSleepMaintenanceRequest {
            handle: opened.handle,
            max_memories: 100,
            apply_decay: true,
            evaluate_archival: true,
            apply_archival_deletes: false,
            run_consolidation: true,
            max_consolidation_clusters: 4,
            consolidation_min_cluster_size: 2,
            consolidation_similarity_threshold: 0.85,
            link_entities: true,
        })
        .expect("run sleep maintenance");
        assert!(sleep.lease_acquired);
        assert!(sleep.processed_memories >= 4);

        close_database(opened.handle).expect("close database");
    }

    #[test]
    fn chunking_uses_character_boundaries() {
        let chunks = chunk_memory_bank("abcd\néfghij", 4).expect("chunk text");
        assert_eq!(chunks, vec!["abcd", "éfgh", "ij"]);
    }
}
