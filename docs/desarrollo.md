# Entorno de desarrollo

> **Estado:** en construcción. Por ahora este documento cubre sólo la **imagen de la aplicación**. La base de datos, Ollama y la recarga automática se van a sumar con Docker Compose en los próximos PRs.

---

## Requisitos previos

- **Linux** o **WSL 2** en Windows. Se verifico en `Ubuntu 22.04 LTS`, Otras distribuciones deberían funcionar si Docker Engine cuenta con instrucciones oficiales de instalación para ellas ([lista en la documentación de Docker](https://docs.docker.com/engine/install/)), pero no se probaron.
- **Docker Engine**, instalado desde el [repositorio oficial de Docker](https://docs.docker.com/engine/install/ubuntu/).
- Tu usuario tiene que poder usar Docker sin `sudo` (pertenecer al grupo `docker`).
- Conexión a internet para el primer build y la primera ejecución.

Para comprobar que está todo instalado:

```bash
docker --version
id -u && id -g
```

Estos dos últimos números son tu UID y GID. Se usan en el siguiente paso.

---

## Construir la imagen

Desde la raíz del repositorio:

```bash
docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
  -t chatbot-unla-dev -f Dockerfile.dev .
```

- `--build-arg UID=... GID=...` crea dentro de la imagen un usuario con **tu mismo UID y GID**. Así, los archivos que genere el contenedor te pertenecen a vos.
- `-t chatbot-unla-dev` le pone nombre a la imagen.
- `-f Dockerfile.dev` indica qué Dockerfile usar.
- `.` indica que el contexto de build es la carpeta actual, la raíz del repositorio.

La primera vez tarda unos `35 segundos`, porque descarga la imagen base. Después, con la caché de Docker, tarda unos `3 segundos`. Estos tiempos corresponden solo al build de la imagen: las dependencias de Maven se descargan al ejecutar la aplicación por primera vez, no durante el build.

---

## Cómo está armada la imagen

El `Dockerfile.dev` tiene **una sola etapa**, basada en `eclipse-temurin:17-jdk-noble`. A diferencia de una imagen de producción, **no contiene el código de la aplicación**: lo aporta tu carpeta del proyecto mediante un *bind mount* en `/app`.

Características:

- **El código no está en la imagen:** se comparte desde tu carpeta. Cada cambio se ve sin reconstruir la imagen.
- **No corre como root:** el proceso se ejecuta con el usuario `devuser`, con tu mismo UID y GID. Los archivos que se crean (como `target/`) quedan a tu nombre.
- **Incluye el JDK:** en desarrollo se compila dentro del contenedor.
- **Usa el wrapper de Maven (`mvnw`):** todos compilan con la versión de Maven que fija el proyecto en `.mvn/wrapper/`.
- **Caché de dependencias:** la carpeta `/home/devuser/.m2` se crea en la imagen con su dueño. Al montar un volumen ahí, Maven puede escribir y las dependencias se guardan entre ejecuciones.
- **Incluye `inotify-tools`:** queda instalado para el script de recarga automática, que se agrega en un PR posterior.
- **`CMD` reemplazable:** por defecto ejecuta `sh mvnw spring-boot:run`, pero se puede cambiar desde la terminal. Usa `sh` para no depender del permiso de ejecución de `mvnw` en tu disco.

El archivo `.dockerignore` evita que se envíen al build el historial de git (`.git`), las compilaciones locales (`target/`), los archivos `.env` y la configuración de los editores.

---

## Verificar la imagen

```bash
# Debe responder "devuser": la aplicación no corre como root
docker run --rm chatbot-unla-dev whoami

# Debe coincidir con tu UID en el host
docker run --rm chatbot-unla-dev id -u

# Debe salir vacío: la imagen no contiene el código fuente
docker run --rm chatbot-unla-dev ls -A /app

# Debe mostrar una ruta: inotify-tools está instalado
docker run --rm chatbot-unla-dev which inotifywait
```

Para comprobar que la imagen compila el proyecto:

```bash
docker run --rm \
  -v "$(pwd)":/app \
  -v maven-cache:/home/devuser/.m2 \
  chatbot-unla-dev sh mvnw -B compile
```

- `-v "$(pwd)":/app` comparte tu proyecto con el contenedor.
- `-v maven-cache:/home/devuser/.m2` guarda las dependencias descargadas en un volumen.

Tiene que terminar con `BUILD SUCCESS`. La primera vez tarda, porque descarga Maven y las dependencias. Después, los archivos generados deben ser tuyos y no de root:

```bash
ls -ln target
```

---

## Limitaciones actuales

- **La imagen todavía no arranca sola.** La aplicación necesita MySQL. Si se ejecuta sin una base de datos disponible, Spring Boot inicia y después falla con `Communications link failure`. Es el comportamiento esperado hasta que se agregue Docker Compose.
- **La imagen todavía no arranca sola.** La aplicación necesita MySQL al iniciar: Hibernate se conecta a la base para verificar y crear las tablas, y si no puede, Spring Boot aborta el arranque con `Communications link failure`. No es un defecto de la imagen sino un requisito de la aplicación. Además, `application.properties` apunta a `localhost:3306`, y dentro de un contenedor `localhost` es el propio contenedor, que no tiene base de datos. La solución definitiva es Docker Compose (PR siguiente), que levanta MySQL y conecta ambos servicios por nombre. Mientras tanto, en Linux se puede probar con un contenedor `mysql:8.0` aparte y `--network host`.
- **La recarga automática depende de que el editor compile el código.** La imagen no incluye un proceso que recompile al guardar. Con el IDE abierto, su extensión de Java genera los `.class` en el `target/` compartido y Spring Boot DevTools reinicia la aplicación; con el editor cerrado, los cambios no se aplican. El script basado en `inotify-tools`, que ya está instalado en la imagen, lo resolverá en un PR posterior.
- **La configuración todavía está fija en `application.properties`** (`localhost`, `root/root`, URL de Ollama). Se pasa a variables de entorno en un PR aparte. Ahí mismo hay que corregir el typo `allowPublicKeyRetrival` por `allowPublicKeyRetrieval`: mientras tanto, la conexión a MySQL 8 con un usuario sin SSL falla con `Public Key Retrieval is not allowed`.
