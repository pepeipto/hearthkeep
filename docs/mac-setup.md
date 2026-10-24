# Preparar el Mac para seguir con Hearthkeep

Lista para seguir en orden. Lo marcado como "sin verificar" no lo he podido comprobar en el Mac.

## 1. Herramientas básicas

- [ ] Homebrew instalado (https://brew.sh).
- [ ] Git y GitHub CLI:

```bash
brew install git gh
```

- [ ] Identidad de git (la misma que en Windows, o la de tu elección):

```bash
git config --global user.name "Carlos Fernandez Medina"
git config --global user.email "tu-email"
```

- [ ] Iniciar sesión en GitHub (elige la cuenta que quieras usar; en Windows el repositorio está en `pepeipto`):

```bash
gh auth login
```

## 2. Bajar el trabajo

```bash
git clone https://github.com/pepeipto/hearthkeep.git
cd hearthkeep
```

## 3. Poder ejecutar los tests

- [ ] LuaJIT (semántica de Lua 5.1, como WoW):

```bash
brew install luajit
```

- [ ] Ejecutar la suite desde la raíz del repositorio. Debe terminar con `110 passed, 0 failed`:

```bash
luajit tests/run.lua
```

## 4. Claude en el Mac

- [ ] Instalar Claude Code o la app de escritorio de Claude e iniciar sesión con la misma cuenta.
- [ ] Activar los mismos plugins y skills que en Windows. Los que usé en esta sesión:
  - Plugin `superpowers`: brainstorming, writing-plans, executing-plans, test-driven-development, requesting-code-review, finishing-a-development-branch.
  - `anthropic-skills`: deep-research y el resto que ya tengas activos.
  - Cómo se instalan depende de tu cuenta; búscalos en el catálogo de plugins de claude.ai (sin verificar los pasos exactos en el Mac).
- [ ] Abrir la sesión dentro de la carpeta `hearthkeep` clonada.
- [ ] La memoria, el historial y los ajustes de la sesión de Windows no se copian. Lo importante está en el spec, el plan y los docs del repositorio.

## 5. Probar el addon en el cliente de WoW

- [ ] Copiar las dos carpetas `Hearthkeep` y `Hearthkeep_Alts` a la carpeta de AddOns del cliente de Forever. La ruta suele ser de la forma `/Applications/World of Warcraft/<carpeta del cliente>/Interface/AddOns/`, pero no sé cómo se llama la carpeta de Forever (sin verificar).
- [ ] Seguir `docs/launch-day-checklist.md` paso a paso.

## 6. Generar el zip de publicación

`scripts/build.ps1` es de PowerShell. En el Mac basta con esto, desde la raíz del repositorio:

```bash
mkdir -p dist && zip -r dist/Hearthkeep-0.1.0.zip Hearthkeep Hearthkeep_Alts
```

Comprueba con `unzip -l dist/Hearthkeep-0.1.0.zip` que las rutas empiezan por `Hearthkeep/` y `Hearthkeep_Alts/`. Cambia el número si cambia la versión del `.toc`.

## 7. Mockup y capturas

- [ ] Regenerar el mockup HTML (funciona igual en el Mac):

```bash
luajit scripts/gen-mockup.lua
```

- [ ] El PNG del mockup se exportó con Edge en modo headless en Windows. En el Mac, ábrelo en cualquier navegador y haz captura, o usa Chrome en modo headless (sin verificar).
- [ ] Las capturas y el vídeo reales de la web se hacen con el cliente de Forever, siguiendo `docs/media/shot-list.md` y `docs/media/video-storyboard.md`.

## 8. n8n (pendiente de definir)

Todavía no hay nada configurado ni decidido. Antes de instalarlo, decide qué quieres automatizar. Para probarlo en local:

```bash
npx n8n
```

Necesita Node.js (`brew install node`) y abre la interfaz en http://localhost:5678. También se puede ejecutar con Docker.

## 9. Antes de seguir trabajando

- [ ] `git pull` al empezar cada sesión y `git push` al terminar, para no pisar cambios entre Windows y Mac.
- [ ] No se sube nunca la carpeta `.superpowers/` (ya está en `.gitignore`).
