final class DemoPersona {
  const DemoPersona({
    required this.id,
    required this.name,
    required this.role,
    required this.projectContext,
    required this.memoryBank,
    required this.scenario,
  });

  final String id;
  final String name;
  final String role;
  final String projectContext;
  final String memoryBank;
  final DemoScenario scenario;
}

final class DemoScenario {
  const DemoScenario({
    required this.name,
    required this.steps,
  });

  final String name;
  final List<DemoScenarioStep> steps;
}

final class DemoScenarioStep {
  const DemoScenarioStep({
    required this.title,
    required this.userPrompt,
    required this.expectedMemorySignal,
    this.startsNewSession = false,
  });

  final String title;
  final String userPrompt;
  final String expectedMemorySignal;
  final bool startsNewSession;
}

const demoPersonas = <DemoPersona>[
  DemoPersona(
    id: 'synapse_flutter',
    name: 'Synapse engineer',
    role: 'Flutter app developer',
    projectContext: 'synapse_flutter_memory_demo',
    memoryBank: '''
Project Synapse is a Flutter and Dart cross platform app.
The active mobile stack uses Flutter widgets, Dart isolates, Isar or SQLite local cache, and Supabase sync.
The user dislikes answers that drift into native Swift unless native iOS was explicitly requested.
Large share sheet payload work should be handled through Flutter isolates, chunking, and platform channel boundaries only where needed.
The user prefers OpenRouter compatible chat endpoints for demos.
Pain signal: previous benchmark failed because the model forgot Synapse is Flutter and answered with Swift, UIKit, SwiftUI, Core ML, and GCD.
''',
    scenario: DemoScenario(
      name: 'Context drift stress test',
      steps: [
        DemoScenarioStep(
          title: 'Performance bottleneck',
          userPrompt:
              'Synapse freezes when importing a massive share sheet text payload. How should I move parsing off the UI thread?',
          expectedMemorySignal:
              'A memory aligned answer should mention Dart isolates or compute and avoid Swift concurrency.',
        ),
        DemoScenarioStep(
          title: 'Architecture recall',
          userPrompt:
              'What storage and sync assumptions should you keep in mind before proposing this fix?',
          expectedMemorySignal:
              'The with-memory answer should recall Flutter, local cache, and Supabase.',
        ),
        DemoScenarioStep(
          title: 'Correction handling',
          userPrompt:
              'Correction: for this module, prefer SQLite over Isar. What changes in the implementation plan?',
          expectedMemorySignal:
              'The activity feed should show a correction or stored turn.',
        ),
        DemoScenarioStep(
          title: 'New session recall',
          userPrompt:
              'We are in a new chat. Synapse import is slow again. What stack-specific fix should I start with?',
          expectedMemorySignal:
              'Memory should preserve the Flutter alignment across a fresh chat session.',
          startsNewSession: true,
        ),
      ],
    ),
  ),
  DemoPersona(
    id: 'dinner_planner',
    name: 'Dinner planner',
    role: 'Personal assistant',
    projectContext: 'dinner_planning_demo',
    memoryBank: '''
Alex avoids peanuts and cashews.
Alex prefers vegetarian meals on weekdays.
Alex likes Thai basil, mushrooms, and sparkling water.
The last dinner plan failed because it included a peanut sauce.
''',
    scenario: DemoScenario(
      name: 'Preference recall',
      steps: [
        DemoScenarioStep(
          title: 'Menu suggestion',
          userPrompt:
              'What should I remember when planning dinner for Alex next week?',
          expectedMemorySignal:
              'Memory should recall vegetarian weekday preference and nut avoidance.',
        ),
        DemoScenarioStep(
          title: 'Pain signal',
          userPrompt:
              'Can I make satay noodles for Alex if I remove the cashews?',
          expectedMemorySignal:
              'Memory should flag the prior peanut sauce failure.',
        ),
        DemoScenarioStep(
          title: 'New preference',
          userPrompt:
              'Update: Alex now prefers mild spice. Suggest a safe menu.',
          expectedMemorySignal:
              'The turn should be stored as a recent memory for later recall.',
        ),
      ],
    ),
  ),
  DemoPersona(
    id: 'product_manager',
    name: 'Product manager',
    role: 'Launch planning partner',
    projectContext: 'launch_planning_demo',
    memoryBank: '''
The product launch is for a local first AI memory app.
The launch goal is trust and repeat usage, not viral growth.
The team wants a small beta with power users before public marketing.
Avoid proposing cloud only architecture because offline behavior is a core promise.
The user cares about memory inspection, deletion, and clear provenance.
''',
    scenario: DemoScenario(
      name: 'Roadmap continuity',
      steps: [
        DemoScenarioStep(
          title: 'Launch plan',
          userPrompt:
              'Give me a launch checklist for the memory app that matches our current constraints.',
          expectedMemorySignal:
              'Memory should anchor on local first, beta users, and provenance.',
        ),
        DemoScenarioStep(
          title: 'Contradiction check',
          userPrompt:
              'Should we remove local storage and make everything cloud only for faster iteration?',
          expectedMemorySignal:
              'Memory should resist the cloud only suggestion because it conflicts with a core promise.',
        ),
      ],
    ),
  ),
];

DemoPersona demoPersonaById(String id) {
  return demoPersonas.firstWhere(
    (persona) => persona.id == id,
    orElse: () => demoPersonas.first,
  );
}
