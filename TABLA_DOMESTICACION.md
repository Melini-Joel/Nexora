# Tabla de domesticación — NEXORA

Para domesticar un animal: **poné su comida favorita en la barra rápida, tenela en la mano, acercate y apretá E** las veces que indica la tabla. Cada vez se consume 1 unidad.
- El progreso se ve sobre el animal ("domando 2/6").
- **Si lo lastimás, pierde la confianza** y el progreso vuelve a 0.
- Los animales agresivos (jabalí, lobo y oso) se calman cuando les das de comer, pero cuidado mientras tanto.

| Animal | Dónde vive | Comida | Cantidad | Cómo se consigue la comida | Qué hace domesticado |
|---|---|---|---|---|---|
| 🐇 **Conejo** | Pradera | Bayas | 3 | Arbustos con frutos rojos (pradera y bosque) | Mascota: te sigue a todos lados |
| 🦌 **Ciervo** | Pradera, Bosque | Bayas | 8 | Arbustos con frutos rojos | Mascota: te sigue y no huye de vos |
| 🐗 **Jabalí** | Bosque, Pradera | Carne cruda | 5 | Cazando animales | Pelea a tu lado contra las sombras (daño 12) |
| 🐺 **Lobo** | Bosque, Tundra | Carne cocida | 6 | Carne cruda cocinada en una fogata | Pelea a tu lado, es rápido y te defiende de noche (daño 14) |
| 🐻 **Oso** | Tundra, Bosque | Carne cocida | 12 | Carne cruda cocinada en una fogata | Guardián: mucha vida y daño (daño 26) |
| 🦎 Lagarto de arena | Desierto | — | — | No se puede domesticar | Se caza por carne y mucho cuero |

## Órdenes a tu mascota
- **E sobre tu mascota:** alterna entre "seguirte" y "quedarse quieta".
- Si te alejás mucho (más de 45 m), la mascota te alcanza sola.
- Si te desconectás, tu mascota se queda esperando en el lugar.
- Las mascotas que pelean atacan solas a las sombras que se acerquen.

## Comportamiento de los animales salvajes
| Animal | Comportamiento | Vida | Lo que deja al cazarlo |
|---|---|---|---|
| Conejo | Huye | 20 | Carne cruda x1, Cuero x1 |
| Ciervo | Huye (muy rápido) | 60 | Carne cruda x4, Cuero x3 |
| Lagarto de arena | Huye | 35 | Carne cruda x2, Cuero x3 |
| Jabalí | Se defiende si lo atacás | 90 | Carne cruda x5, Cuero x4 |
| Lobo | Tranquilo de día, **ataca de noche** | 80 | Carne cruda x3, Cuero x4 |
| Oso | Se defiende si lo atacás (muy fuerte) | 260 | Carne cruda x10, Cuero x12 |

## Criaturas de la noche (no se domestican)
| Criatura | Vida | Daño | Lo que deja |
|---|---|---|---|
| Sombra | 60 | 7 | Fragmentos de metal x3 · 30% de chance de un **plano** |
| Bruto sombrío (desde el día 2) | 170 | 16 | Fragmentos de metal x10, Cuero x4 · 60% de chance de un **plano** |

Las sombras se queman con la luz del sol al amanecer.

> Para cambiar estos valores: `scripts/data/creature_db.gd`.
