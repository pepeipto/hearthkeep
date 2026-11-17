# Guía de prueba: Hearthkeep 0.3.0 (todo en uno)

Un solo addon, `Hearthkeep`. No necesita ningún addon de otros autores.

## 1. Instalar

**En tu PC ya está instalado** (17-11-2026; copia de las carpetas antiguas guardada). Para
otro PC:

1. Cierra el juego.
2. Copia la carpeta `Hearthkeep` del zip (`dist/Hearthkeep-0.3.0.zip`) en
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`.
3. **Borra** las carpetas antiguas si siguen ahí: `Hearthkeep_Alts`, `Hearthkeep_Modes`,
   `Hearthkeep_Bosses` (ahora van dentro de `Hearthkeep`).
4. Abre el juego y entra con un personaje.

## 2. Primera vez

En una instalación nueva sale el asistente: idioma → aspecto → **Mínimo** o
**Recomendado**. Al terminar se abre la ventana principal. **Tú ya lo habías hecho antes**,
así que no saldrá solo: escribe `/hk setup` y elige **Recomendado** para encender los módulos.

## 3. La ventana principal: `/hk`

A la izquierda, los módulos por grupos (verde `+` = encendido, gris `-` = apagado). A la
derecha, la página del módulo con **Encender/Apagar** y **Abrir**. Abajo: perfiles Mínimo y
Recomendado, y **Mover HUD** (para colocar los elementos de pantalla; `/hk hud reset` los
devuelve a su sitio).

## 4. Qué probar (marca cada uno)

| Grupo | Módulo | Cómo probarlo | ¿Funciona? |
|-------|--------|---------------|------------|
| Aventura | Personajes | `/hk alts`, botón del minimapa (clic derecho = menú) | |
| Aventura | Notas de jefes | `/hk bosses` | |
| Aventura | Entrenamiento | habla con el entrenador de tu clase, luego `/hk train` | |
| Aventura | Profesiones | abre tu profesión, luego `/hk prof` | |
| Aventura | Punto de ruta | `/hk way 50 50 prueba` → flecha y distancia; `/hk way clear` | |
| Combate | Puntuación de equipo | `/hk gear`; pasa el ratón por ti y por otros jugadores | |
| Combate | Sets de equipo | `/hk sets save prueba`, cámbiate algo, `/hk sets equip prueba` | |
| Combate | Lista de deseos | `/hk want` + mayúsculas-clic en un objeto; mira su descripción | |
| Combate | Grupo | en grupo: `/hk group` (los que tengan Hearthkeep salen con puntuación) | |
| Combate | Amenaza | ataca a un enemigo en grupo; `/hk threat` | |
| Combate | Bufos | dentro de una mazmorra sin comida/frasco: debe avisarte | |
| Calidad de vida | XP | mata algo: XP/hora y tiempo para subir; `/hk xp` | |
| Calidad de vida | Bolsas | espacio libre en pantalla; `/hk bags` | |
| Calidad de vida | Vendedor | habla con un vendedor con objetos grises: vende y repara | |
| Calidad de vida | Botín | recoge algo: aparece en la lista; `/hk loot` | |
| Calidad de vida | Barra superior | reloj, FPS, latencia, amigos y hermandad arriba | |
| Utilidades | Macros | `/hk macros`: revisa y explica tus macros | |
| Hearthkeep | Modos de actividad | opcional, viene apagado | |

## 5. Si algo falla

Escribe `/hk debug` y mándame una captura. Ahí salen los errores de cada módulo y qué
funciones del juego faltan. Ningún módulo debería sacar un error rojo: si sale uno,
captura también.

## 6. Lo que aún no está (siguiente versión)

- Diario de mazmorras con botín y mapas, y lista BiS con sugerencias: necesitan datos de
  objetos que todavía no tenemos.
- Guía de misiones con grabador de rutas.
- Buscador de grupo, bendiciones, temporizador de golpes.
