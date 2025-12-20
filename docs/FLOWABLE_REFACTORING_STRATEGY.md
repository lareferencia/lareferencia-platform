# Flowable Integration Strategy & Refactoring Proposal

## 1. Executive Summary
This document outlines the strategy for migrating the **LA Referencia Platform** from its legacy `NetworkActionManager` task engine to the **Flowable BPMN 2.0 Engine**. It evaluates the current "Wrapper" implementation (Phase 1), identifies critical architectural weaknesses, and proposes a definitive **Service-Adapter Pattern** (Phase 2) to ensure stability, clarity, and maintainability.

## 2. Current Status (Phase 1: The "Wrapper" Approach)
We have achieved a compiling state where legacy `IWorker` components wrap Flowable logic via `AbstractFlowableWorker`.

### Achievements
*   **Compilation**: The project compiles successfully (`mvn clean install`).
*   **Infrastructure**: `WorkflowService`, `WorkflowScheduler`, and BPMN definitions (`harvesting.bpmn20.xml`) are in place.
*   **Refactoring**: Legacy `NetworkActionManager` and XML-based Orchestration (`actions.xml`) have been disconnected.

### Critical Critique (The "Uncanny Valley")
Despite functioning, the current implementation suffers from architectural "smells":
1.  **ThreadLocal Fragility**: `HarvestingWorker` uses `ThreadLocal` to bridge Flowable's stateless execution with legacy event listeners. This is dangerous in async environments.
2.  **Leaky Abstractions**: Workers are forced to implement `JavaDelegate` and handle `DelegateExecution`, mixing business logic with process engine infrastructure.
3.  **State Re-hydration**: Workers repeatedly fetch the `Network` entity from the DB in every step, rather than receiving a clean context object.

---

## 3. Proposed Architecture: The Service-Adapter Pattern

To resolve these issues, we recommend the **Service-Adapter Pattern** (also known as the "Orchestrator Only" approach). This decouples pure business logic from the process engine.

### Core Concept
1.  **The Service (`HarvestingService`)**: A pure Spring `@Service` (Singleton) containing business logic. It knows **nothing** about Flowable. It accepts simple POJOs (`HarvestingRequest`) and returns results (`HarvestingResult`).
2.  **The Delegate (`HarvestingDelegate`)**: An Adapter class that implements `JavaDelegate`. It is the *only* place that touches Flowable APIs (`DelegateExecution`). It extracts variables, builds the Request POJO, calls the Service, and sets output variables.

### Architecture Diagram
```mermaid
graph LR
    subgraph Flowable Engine
        Process[BPMN Process] -->|Execute| Delegate[HarvestingDelegate]
    end

    subgraph Business Logic Layer
        Delegate -->|Call(Network, Config)| Service[HarvestingService]
        Service -->|Uses| Harvester[OAIHarvester]
        Service -->|Uses| Repo[OAIRecordRepository]
    end
```

### Benefits
*   **Zero ThreadLocals**: Context is passed explicitly as method arguments.
*   **Testability**: `HarvestingService` can be unit-tested with standard mocks, without needing a Process Engine.
*   **Clean Separation**: Upgrading Flowable or changing the engine in the future won't require touching business logic.

---

## 4. Implementation Roadmap

### Step 1: Refactor Workers (The "Service" Layer)
*   **Action**: Modify `HarvestingWorker` and `ValidationWorker`.
*   **Change**: remove `extends AbstractFlowableWorker` and `implements JavaDelegate`.
*   **New Signature**:
    ```java
    public void execute(Network network, boolean incremental, ...)
    ```
*   **Goal**: Pure Java logic. No `DelegateExecution`.

### Step 2: Create Delegates (The "Adapter" Layer)
*   **Action**: Create `org.lareferencia.core.flowable.delegates.HarvestingDelegate`.
*   **Logic**:
    ```java
    public void execute(DelegateExecution execution) {
        Long networkId = (Long) execution.getVariable("networkId");
        Network network = repository.findById(networkId).orElseThrow();
        harvestingWorker.execute(network); // Call the service
    }
    ```

### Step 3: Cleanup
*   **Action**: Delete `AbstractFlowableWorker`.
*   **Action**: Delete unused legacy XML configurations (`actions.xml`, `entity.actions.xml`).

---

## 5. Next Steps
Once approved, we will execute the **Implementation Roadmap** defined above. This will involve rewriting the internal logic of `HarvestingWorker` to remove the `ThreadLocal` pattern and creating the accompanying `Delegate` classes.
