# Tareas: <nombre de la feature>

- **Plan**: ./plan.md
- **Estado**: borrador <!-- borrador | aprobado -->

Leyenda: `[ ]` pendiente · `[~]` en progreso · `[x]` hecha · `[!]` bloqueada · `[-]` descartada · `[P]` paralelizable

Formato de cada tarea (una línea):
`- [ ] T001 [P] Descripción imperativa — archivos: ruta/a, ruta/b — cubre: RF-001 — verifica: <comando o criterio observable>`

Dependencias: cada fase depende de la anterior; dentro de una fase se ejecuta en orden salvo `[P]`.
Dependencias explícitas: añadir `— depende: T00X`.

## Fase 1: Preparación

- [ ] T001 …

## Fase 2: Pruebas

- [ ] T00X …

## Fase 3: Núcleo

- [ ] T00X …

## Fase 4: Integración

- [ ] T00X …

## Fase 5: Pulido

- [ ] T00X …

## Correcciones de verificación

<!-- /sdd-verify añade aquí tareas si detecta fallos -->

## Cobertura

| Requisito | Tareas |
|---|---|
| RF-001 | T00X |
