---
description: Detectar ambigüedades en la spec activa y resolverlas con preguntas al usuario
argument-hint: "[foco opcional]"
---

Foco: $ARGUMENTS

Sigue `.sdd/PROTOCOL.md`.

1. Lee `.sdd/STATE.md` → feature activa; lee su `spec.md` y `.sdd/constitution.md`. Sin feature activa: dilo y detente.
2. **Write-ahead**: `STATE.md` → `fase: clarify`, siguiente paso «Ronda de clarificación de <feature>».
3. **Analiza la cobertura** de la spec: alcance, actores y permisos, flujos y casos borde, datos y volúmenes, manejo de errores, rendimiento/seguridad/privacidad, integraciones externas, criterios de aceptación medibles, terminología. Incluye todos los `[NEEDS CLARIFICATION]`.
4. **Prioriza** por impacto × incertidumbre. Máximo 5 preguntas por ronda, **de una en una** (usa AskUserQuestion si está disponible), cada una con 2-4 opciones y una recomendada con su motivo.
5. **Persiste cada respuesta en cuanto la recibas**, no al final:
   - añádela en `## 11. Clarificaciones` bajo `### Sesión AAAA-MM-DD` como `- P: … → R: …`;
   - aplica el cambio a la sección afectada (requisitos, criterios, supuestos, fuera de alcance) y elimina el marcador correspondiente.
   Así, si la sesión se corta a mitad de ronda, lo ya respondido no se pierde.
6. Al terminar la ronda: si quedan ambigüedades de alto impacto, enuméralas y propón otra ronda. Cambia `Estado:` de la spec a `aclarada` si no queda nada bloqueante.
7. **Persistencia**: journal (decisiones tomadas); `STATE.md` con siguiente paso.
8. Pide al usuario que **apruebe** la spec. Cuando lo haga, pon `Estado: aprobada` en la cabecera, registra en journal y deja `/sdd-plan` como siguiente paso.
