# geducand-imapsync — atajos de gestion
#
# Ejecuta 'make' o 'make help' para ver los comandos disponibles.

# bash, no sh: 'read -s' (entrada sin eco) es una extension de bash.
SHELL := /bin/bash

COMPOSE := docker compose
SERVICE := imapsync
SECRETS := password_corporativo_junta password_geducaand

.DEFAULT_GOAL := help
.PHONY: help install check-config up down restart build test sync-once logs status shell clean

# Pide una contrasena por prompt y la escribe en el fichero, sin eco en
# pantalla y sin pasar por la linea de comandos (printf es builtin, asi que
# no aparece en 'ps'). El fichero se crea con permisos 600 antes de escribir.
#   $(1) = fichero destino    $(2) = descripcion para el prompt
define pedir_secreto
	@if [ -s "$(1)" ]; then \
		read -rp "  $(1) ya tiene contenido. Sobrescribir? [s/N] " resp; \
		if [ "$$resp" != "s" ]; then echo "    se conserva la actual"; exit 0; fi; \
	fi; \
	if [ ! -t 0 ]; then \
		echo "  ! sin terminal interactiva: $(1) queda vacio"; \
		[ -f "$(1)" ] || install -m 600 /dev/null "$(1)"; \
		exit 0; \
	fi; \
	read -rsp "  Contrasena — $(2): " clave; echo ""; \
	if [ -z "$$clave" ]; then \
		echo "    vacia: no se escribe nada, puedes rellenarla luego"; \
		[ -f "$(1)" ] || install -m 600 /dev/null "$(1)"; \
	else \
		install -m 600 /dev/null "$(1)"; \
		printf '%s' "$$clave" > "$(1)"; \
		echo "  + $(1) guardada ($${#clave} caracteres)"; \
	fi
endef

help: ## Muestra esta ayuda
	@echo "geducand-imapsync — comandos disponibles:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Primera vez:  make install  →  editar .env y los ficheros de contrasena  →  make test  →  make up"

install: ## Crea .env y pide las contrasenas por prompt
	@if [ -f .env ]; then \
		echo "  = .env ya existe, no se toca"; \
	else \
		cp .env.example .env; \
		echo "  + .env creado desde .env.example"; \
	fi
	@echo ""
	@echo "Contrasenas (no se muestran al escribirlas; Enter deja el fichero vacio):"
	$(call pedir_secreto,password_corporativo_junta,buzon corporativo de la Junta)
	$(call pedir_secreto,password_geducaand,App Password de Google para g.educaand.es)
	@echo ""
	@echo "Los ficheros de contrasena estan en .gitignore: nunca se suben al repositorio."
	@echo "password_geducaand debe ser una App Password (requiere 2FA):"
	@echo "  https://myaccount.google.com/apppasswords"
	@echo ""
	@echo "Siguiente paso: revisa SOURCE_USER y DEST_USER en .env, y lanza 'make test'."

# Interno: no lleva '##' para no aparecer en 'make help'.
check-config:
	@test -f .env || { echo "ERROR: falta .env. Ejecuta 'make install'."; exit 1; }
	@for s in $(SECRETS); do \
		test -f $$s || { echo "ERROR: falta $$s. Ejecuta 'make install'."; exit 1; }; \
		test -s $$s || { echo "ERROR: $$s esta vacio. Escribe la contrasena dentro."; exit 1; }; \
	done

build: ## Construye la imagen
	$(COMPOSE) build

up: check-config ## Levanta el contenedor en segundo plano
	$(COMPOSE) up -d --build
	@echo ""
	@echo "Contenedor levantado. Sigue el log con: make logs"

down: ## Para y elimina el contenedor
	$(COMPOSE) down

restart: ## Reinicia el contenedor
	$(COMPOSE) restart

test: check-config ## Ejecucion unica en simulacion y verbosa (no modifica nada)
	@echo "Ejecucion de prueba: DRY_RUN=true, no se escribe ni se borra nada."
	@echo ""
	$(COMPOSE) run --rm \
		-e RUN_ONCE=true \
		-e DRY_RUN=true \
		-e VERBOSE=true \
		$(SERVICE)

sync-once: check-config ## Una unica sincronizacion REAL (sin simulacion)
	@echo "ATENCION: sincronizacion real, con borrado en origen si DELETE_SOURCE=true."
	@printf "Continuar? [s/N] " && read r && [ "$$r" = "s" ]
	$(COMPOSE) run --rm -e RUN_ONCE=true -e VERBOSE=true $(SERVICE)

logs: ## Sigue el log del contenedor
	$(COMPOSE) logs -f

status: ## Estado del contenedor y tamano de los logs
	@$(COMPOSE) ps
	@echo ""
	@if [ -d logs ]; then du -sh logs 2>/dev/null; ls -la logs/ 2>/dev/null; else echo "(aun no hay logs)"; fi

shell: ## Abre una shell dentro del contenedor
	$(COMPOSE) exec $(SERVICE) /bin/bash

clean: ## Elimina contenedor, imagen y logs (conserva .env y contrasenas)
	@printf "Se borraran contenedor, imagen y logs. Continuar? [s/N] " && read r && [ "$$r" = "s" ]
	$(COMPOSE) down --rmi local -v
	rm -rf logs
	@echo "Limpiado. .env y los ficheros de contrasena se han conservado."
