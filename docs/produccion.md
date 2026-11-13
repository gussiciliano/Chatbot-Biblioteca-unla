# 🐳 Entorno de producción

> **Estado:** en construcción. Por ahora este documento cubre sólo la **imagen de la aplicación**. La base de datos, Ollama y el reverse proxy se van a sumar con Docker Compose en los próximos PRs.

---

## ⚙️ Requisitos previos

- **Linux**, o **WSL 2** en Windows con cualquier distribución que Docker Engine soporte oficialmente (por ejemplo Ubuntu, Debian o Fedora). Estos pasos se probaron en Ubuntu.
  - Tiene que ser WSL **2**: Docker Engine necesita un kernel de Linux real, y WSL 1 no lo tiene. Para ver la versión, en PowerShell: `wsl -l -v` (columna `VERSION`).
- **Docker Engine** y el plugin **Docker Compose**, instalados desde el [repositorio oficial de Docker](https://docs.docker.com/engine/install/) siguiendo las instrucciones de tu distribución. No se usa Docker Desktop.
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

## 🧪 Probar la imagen con una base de datos temporal

La aplicación necesita MySQL para arrancar. Si se ejecuta sola, con `docker run --rm chatbot-unla`, falla con `Communications link failure`: la configuración busca la base en `localhost:3306`, y **dentro de un contenedor `localhost` es el propio contenedor**, donde no hay ninguna base de datos.

Para probarla, se levanta una MySQL temporal en una red de Docker y se le indica a la aplicación, por variables de entorno, que la busque por el nombre de su contenedor. Las contraseñas de los comandos son de ejemplo, sólo para esta prueba local.

**1. Crear una red y levantar MySQL:**

```bash
docker network create prueba-chatbot

docker run -d --rm --name prueba-mysql --network prueba-chatbot \
  -e MYSQL_ROOT_PASSWORD=prueba-root \
  -e MYSQL_DATABASE=chatbot \
  -e MYSQL_USER=chatbot \
  -e MYSQL_PASSWORD=prueba \
  mysql:8.4
```

Esperar a que MySQL termine de inicializarse: en el log (`docker logs -f prueba-mysql`), el mensaje `ready for connections` aparece dos veces, y la que indica que está listo es la que dice `port: 3306`. Cortar el log con Ctrl+C; MySQL sigue corriendo.

**2. Levantar la aplicación en la misma red:**

```bash
docker run --rm --name prueba-app --network prueba-chatbot -p 8080:8080 \
  -e SPRING_DATASOURCE_URL="jdbc:mysql://prueba-mysql:3306/chatbot?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true" \
  -e SPRING_DATASOURCE_USERNAME=chatbot \
  -e SPRING_DATASOURCE_PASSWORD=prueba \
  -e MAIL_USERNAME=prueba@example.com \
  -e MAIL_PASSWORD=no-se-usa \
  chatbot-unla
```

- `prueba-mysql`, en la URL, es el nombre del contenedor de MySQL: dentro de una red de Docker, los contenedores se encuentran por nombre.
- Las variables `SPRING_DATASOURCE_*` reemplazan los valores de `application.properties` sin reconstruir la imagen.
- `MAIL_USERNAME` es obligatoria para que la aplicación arranque. En esta prueba no se envían correos, así que alcanza con valores de ejemplo.
- La URL va entre comillas porque contiene `&`, que la terminal interpretaría como otra instrucción.

Cuando el log muestre `Started ChatbotApplication`, la aplicación está disponible en http://localhost:8080. El chat todavía no responde: ver "Limitaciones actuales", más abajo.

**3. Limpiar.** Detener la aplicación con Ctrl+C y después:

```bash
docker stop prueba-mysql
docker network rm prueba-chatbot
```

Los dos contenedores se borran solos al detenerse (`--rm`), y la base de datos se descarta con ellos.

---

## ⚠️ Limitaciones actuales

- **El chat todavía no funciona dentro del contenedor.** La dirección de Ollama está escrita en el código Java como `http://localhost:11434`, así que dentro del contenedor la aplicación lo busca en sí misma y falla. A diferencia de la base de datos, no se puede cambiar con una variable de entorno: hay que parametrizarla en el código.
- **La configuración todavía está dentro de la imagen.** `application.properties` se empaqueta en el `.jar` con los valores que tiene hoy. Hasta que la configuración se pase por variables de entorno, **no hay que publicar esta imagen en ningún registry**.
