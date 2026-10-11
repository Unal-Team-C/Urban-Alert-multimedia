# Especificación: <nombre de la feature>

- **ID**: NNN-slug
- **Estado**: borrador <!-- borrador | aclarada | aprobada | implementada -->
- **Creada**: AAAA-MM-DD
- **Entrada original**: "<descripción literal del usuario>"

## 1. Resumen

<2-4 frases: qué se construye y para quién.>

## 2. Problema y contexto

<Por qué hace falta, situación actual, valor esperado.>

## 3. Usuarios y actores

- **<rol>**: <qué necesita>

## 4. Historias de usuario

### HU-1: <título> (Prioridad: P1)

Como <rol> quiero <acción> para <beneficio>.

**Criterios de aceptación**
1. Dado <contexto>, cuando <acción>, entonces <resultado observable>.

### Casos borde

- ¿Qué ocurre cuando …?

## 5. Requisitos funcionales

- **RF-001**: El sistema DEBE …

## 6. Requisitos no funcionales

- **RNF-001**: <rendimiento, seguridad, accesibilidad, i18n… siempre medible>

## 7. Entidades clave

<Solo si hay datos. Qué representa cada entidad y atributos relevantes, sin tipos ni esquema de BD.>

## 8. Fuera de alcance

- …

## 9. Supuestos

- …

## 10. Métricas de éxito

- **MS-001**: <medible y agnóstica de tecnología>

## 11. Clarificaciones

<!-- /sdd-clarify añade aquí:
### Sesión AAAA-MM-DD
- P: … → R: … -->

---

### Checklist de calidad (autorrevisión antes de entregar)

- [ ] Sin detalles de implementación (lenguajes, frameworks, APIs, estructura de código)
- [ ] Cada requisito es testeable y no ambiguo
- [ ] Criterios de aceptación con resultado observable
- [ ] Casos borde identificados
- [ ] Alcance acotado (fuera de alcance explícito)
- [ ] Como máximo 3 `[NEEDS CLARIFICATION]` pendientes
- [ ] Coherente con `.sdd/constitution.md`
