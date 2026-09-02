# Workflow: estado actual y evolución

`workflow.engine=legacy` es el valor predeterminado y usa `TaskManager`, acciones XML y `LegacyNetworkActionExecutor`. `workflow.engine=flowable` activa `WorkflowService`, delegates y procesos BPMN bajo `config/processes/`. Las configuraciones son condicionales.

Las acciones se resuelven desde la configuración de la red y se ejecutan con su contexto. Los workers comparten el contrato de ejecución; la coordinación pertenece al motor seleccionado.

Cualquier migración completa a Flowable debe definir compatibilidad de acciones, recuperación, cancelación, observabilidad y pruebas de equivalencia. Hasta entonces, cada runbook debe indicar explícitamente el motor activo.
