# 🐳 Entorno de producción

> **Estado:** en construcción. Por ahora este documento cubre sólo la **imagen de la aplicación**. La base de datos, Ollama y el reverse proxy se van a sumar con Docker Compose en los próximos PRs.

---

## ⚙️ Requisitos previos

- **Linux** o **WSL 2** con Ubuntu en Windows.
- **Docker Engine** y el plugin **Docker Compose**, instalados desde el [repositorio oficial de Docker](https://docs.docker.com/engine/install/ubuntu/). No se usa Docker Desktop.
- Tu usuario tiene que poder usar Docker sin `sudo` (pertenecer al grupo `docker`).
- Conexión a internet para el primer build.

Para comprobar que está todo instalado:

```bash
docker --version
docker compose version
```

Usá siempre `docker compose`, con espacio. El comando `docker-compose`, con guion, es una herramienta vieja y no se usa en este proyecto.

---

## 🏗️ Construir la imagen

Desde la raíz del repositorio:

```bash
docker build -t chatbot-unla .
```

- `-t chatbot-unla` le pone nombre a la imagen.
- `.` indica que el contexto de build es la carpeta actual, la raíz del repositorio.

La primera vez tarda unos **2 minutos**, porque descarga la imagen base, Maven y todas las dependencias del proyecto. Después, si sólo cambia el código, tarda unos **20 segundos**: las dependencias quedan en caché mientras no cambie el `pom.xml`.

---

## 🧱 Cómo está armada la imagen

El [`Dockerfile`](../Dockerfile) usa un build **multi-stage** con dos etapas:

| Etapa | Imagen base | Qué hace |
|---|---|---|
| `build` | `eclipse-temurin:17-jdk-noble` | Compila el proyecto con el wrapper de Maven (`mvnw`) y genera el `.jar`. Se descarta al terminar. |
| `production` | `eclipse-temurin:17-jre-noble` | Contiene sólo el JRE y el `.jar`. Es la imagen que se ejecuta. |

Características de la imagen final:

- **No corre como root:** la aplicación se ejecuta con el usuario de sistema `appuser`, que no tiene shell de inicio de sesión.
- **Sin herramientas de desarrollo:** no incluye el JDK, Maven ni el código fuente.
- **Tests salteados en el build:** `-DskipTests` compila los tests pero no los ejecuta, para que construir la imagen no dependa de una base de datos.
- **Caché de dependencias:** primero se copian el wrapper y el `pom.xml` y se descargan las dependencias; recién después se copia `src/`. Así, un cambio de código no vuelve a descargarlas.

El archivo [`.dockerignore`](../.dockerignore) evita que se envíen al build el historial de git, las compilaciones locales (`target/`), los archivos `.env` y la configuración de los editores.

---

## ✅ Verificar la imagen

```bash
# Debe responder "appuser": la aplicación no corre como root
docker run --rm --entrypoint whoami chatbot-unla

# Debe fallar con "executable file not found": la imagen no tiene compilador
docker run --rm --entrypoint javac chatbot-unla -version

# Muestra el tamaño de la imagen (alrededor de 500 MB)
docker images chatbot-unla
```

Para revisar sólo la etapa de compilación, por ejemplo si el build falla:

```bash
docker build --target build -t chatbot-build .
docker run --rm chatbot-build ls target
```

Tiene que aparecer `Chatbot-Biblioteca-unla-0.0.1-SNAPSHOT.jar`.

---

## ⚠️ Limitaciones actuales

- **La imagen todavía no arranca sola.** La aplicación necesita MySQL. Si se ejecuta con `docker run --rm chatbot-unla`, Spring Boot inicia y después falla con `Communications link failure`, porque no hay ninguna base de datos disponible. Es el comportamiento esperado hasta que se agregue Docker Compose.
- **La configuración todavía está dentro de la imagen.** `application.properties` se empaqueta en el `.jar` con los valores que tiene hoy. Hasta que la configuración se pase por variables de entorno, **no hay que publicar esta imagen en ningún registry**.
