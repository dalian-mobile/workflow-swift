/*
 * Copyright 2020 Square Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// Manages a running workflow.
final class WorkflowNode<WorkflowType: Workflow> {
    /// Holds the current state of the workflow
    private var state: WorkflowType.State

    /// Holds the current workflow.
    private var workflow: WorkflowType

    var onOutput: ((Output) -> Void)?

    /// Manages the children of this workflow, including diffs during/after render passes.
    private let subtreeManager = SubtreeManager()

    init(workflow: WorkflowType) {
        /// Get the initial state
        self.workflow = workflow
        self.state = workflow.makeInitialState()

        WorkflowLogger.logWorkflowStarted(ref: self)

        subtreeManager.onUpdate = { [weak self] output in
            self?.handle(subtreeOutput: output)
        }
    }

    deinit {
        WorkflowLogger.logWorkflowFinished(ref: self)
    }

    /// Handles an event produced by the subtree manager
    private func handle(subtreeOutput: SubtreeManager.Output) {
        let output: Output

        switch subtreeOutput {
        case .update(let event, let source):
            /// Apply the update to the current state
            let outputEvent = event.apply(toState: &state)

            /// Finally, we tell the outside world that our state has changed (including an output event if it exists).
            output = Output(
                outputEvent: outputEvent,
                debugInfo: WorkflowUpdateDebugInfo(
                    workflowType: "\(WorkflowType.self)",
                    kind: .didUpdate(source: source)
                )
            )

        case .childDidUpdate(let debugInfo):
            output = Output(
                outputEvent: nil,
                debugInfo: WorkflowUpdateDebugInfo(
                    workflowType: "\(WorkflowType.self)",
                    kind: .childDidUpdate(debugInfo)
                )
            )
        }

        onOutput?(output)
    }

    /// Internal method that forwards the render call through the underlying `subtreeManager`,
    /// and eventually to the client-specified `Workflow` instance.
    /// - Parameter isRootNode: whether or not this is the root node of the tree. Note, this
    /// is currently only used as a hint for the logging infrastructure, and is up to callers to correctly specify.
    /// - Returns: A `Rendering` of appropriate type
    func render(isRootNode: Bool = false) -> WorkflowType.Rendering {
        WorkflowLogger.logWorkflowStartedRendering(ref: self, isRootNode: isRootNode)

        defer {
            WorkflowLogger.logWorkflowFinishedRendering(ref: self, isRootNode: isRootNode)
        }

        return subtreeManager.render { context in
            workflow
                .render(
                    state: state,
                    context: context
                )
        }
    }

    func enableEvents() {
        subtreeManager.enableEvents()
    }

    /// Updates the workflow.
    func update(workflow: WorkflowType) {
        workflow.workflowDidChange(from: self.workflow, state: &state)
        self.workflow = workflow
    }

    func makeDebugSnapshot() -> WorkflowHierarchyDebugSnapshot {
        return WorkflowHierarchyDebugSnapshot(
            workflowType: "\(WorkflowType.self)",
            stateDescription: "\(state)",
            children: subtreeManager.makeDebugSnapshot()
        )
    }
}

extension WorkflowNode {
    struct Output {
        var outputEvent: WorkflowType.Output?
        var debugInfo: WorkflowUpdateDebugInfo
    }
}
