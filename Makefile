# geducand-imapsync — atajos de gestión
#
# Ejecuta 'make' o 'make help' para ver los comandos disponibles.

# bash, no sh: 'read -s' (entrada sin eco) es una extensión de bash.
SHELL := /bin/bash

COMPOSE := docker compose
SERVICE := imapsync
SECRETS := password_corporativo_junta password_geducaand

.DEFAULT_GOAL := help
.PHONY: help install check-config status-config up down restart build test sync-once logs status shell clean

# Valores de .env.example que son marcadores, no configuración real: si una
# variable tiene uno de estos, se pide igualmente.
PLACEHOLDERS := usuario@juntadeandalucia.es usuario@g.educaand.es

# Pide una dirección de correo y la escribe en .env conservando el orden y los
# comentarios del fichero. Enter mantiene el valor actual si ya es válido.
#   $(1) = variable de .env    $(2) = descripción para el prompt
define pedir_usuario
	@actual=$$(grep -E "^$(1)=" .env 2>/dev/null | head -1 | cut -d= -f2-); \
	for ph in $(PLACEHOLDERS); do \
		if [ "$$actual" = "$$ph" ]; then actual=""; fi; \
	done; \
	if [ ! -t 0 ]; then \
		echo "  ! sin terminal interactiva: $(1) se deja como está"; \
		exit 0; \
	fi; \
	while true; do \
		if [ -n "$$actual" ]; then \
			read -rp "  $(2) [$$actual]: " valor; \
			if [ -z "$$valor" ]; then valor="$$actual"; fi; \
		else \
			read -rp "  $(2): " valor; \
		fi; \
		if [ -z "$$valor" ]; then \
			echo "    sin valor: tendrás que ponerlo en .env antes de arrancar"; \
			exit 0; \
		fi; \
		case "$$valor" in \
			*@*.*) break;; \
			*) echo "    «$$valor» no parece una dirección de correo";; \
		esac; \
	done; \
	escapado=$$(printf '%s' "$$valor" | sed 's/[&|\\]/\\&/g'); \
	if grep -qE "^$(1)=" .env; then \
		sed -i "s|^$(1)=.*|$(1)=$$escapado|" .env; \
	else \
		echo "$(1)=$$valor" >> .env; \
	fi; \
	echo "  + $(1)=$$valor"
endef

# Pide una contraseña por prompt y la escribe en el fichero, sin eco en
# pantalla y sin pasar por la línea de comandos (printf es builtin, así que
# no aparece en 'ps'). El fichero se crea con permisos 600 antes de escribir.
#   $(1) = fichero destino    $(2) = descripción para el prompt
define pedir_secreto
	@if [ -s "$(1)" ]; then \
		read -rp "  $(1) ya tiene contenido. ¿Sobrescribir? [s/N] " resp; \
		if [ "$$resp" != "s" ]; then echo "    se conserva la actual"; exit 0; fi; \
	fi; \
	if [ ! -t 0 ]; then \
		echo "  ! sin terminal interactiva: $(1) queda vacío"; \
		[ -f "$(1)" ] || install -m 600 /dev/null "$(1)"; \
		exit 0; \
	fi; \
	read -rsp "  Contraseña — $(2): " clave; echo ""; \
	if [ -z "$$clave" ]; then \
		echo "    vacía: no se escribe nada, puedes rellenarla luego"; \
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
	@echo "Primera vez:  make install  →  make test  →  make up"

install: ## Configura .env y las contraseñas de forma interactiva
	@if [ -f .env ]; then \
		echo "  = .env ya existe, se conserva la configuración actual"; \
	else \
		cp .env.example .env; \
		echo "  + .env creado desde .env.example"; \
	fi
	@echo ""
	@echo "Cuentas de correo:"
	$(call pedir_usuario,SOURCE_USER,Dirección del buzón de origen (Junta))
	$(call pedir_usuario,DEST_USER,Dirección del buzón de destino (g.educaand.es))
	@echo ""
	@echo "Contraseñas (no se muestran al escribirlas; Enter las deja para más tarde):"
	$(call pedir_secreto,password_corporativo_junta,buzón corporativo de la Junta)
	$(call pedir_secreto,password_geducaand,App Password de Google para g.educaand.es)
	@echo ""
	@echo "Los ficheros de contraseña están en .gitignore: nunca se suben al repositorio."
	@echo "password_geducaand debe ser una App Password (requiere 2FA):"
	@echo "  https://myaccount.google.com/apppasswords"
	@echo ""
	@$(MAKE) --no-print-directory status-config

# Internos: no llevan '##' para no aparecer en 'make help'.

# Resumen tras 'make install': dice si ya se puede arrancar o qué falta.
status-config:
	@falta=0; \
	for v in SOURCE_USER DEST_USER; do \
		valor=$$(grep -E "^$$v=" .env 2>/dev/null | head -1 | cut -d= -f2-); \
		for ph in $(PLACEHOLDERS); do \
			if [ "$$valor" = "$$ph" ]; then valor=""; fi; \
		done; \
		if [ -z "$$valor" ]; then echo "  ✗ falta $$v en .env"; falta=1; fi; \
	done; \
	for s in $(SECRETS); do \
		if [ ! -s "$$s" ]; then echo "  ✗ falta la contraseña de $$s"; falta=1; fi; \
	done; \
	if [ "$$falta" = "0" ]; then \
		echo "Todo configurado. Ya puedes lanzar:"; \
		echo "  make test    prueba en simulación, sin tocar ningún buzón"; \
		echo "  make up      arranca el contenedor"; \
	else \
		echo ""; \
		echo "Configuración incompleta. Vuelve a lanzar 'make install' para completarla."; \
	fi

check-config:
	@test -f .env || { echo "ERROR: falta .env. Ejecuta 'make install'."; exit 1; }
	@for v in SOURCE_USER DEST_USER; do \
		valor=$$(grep -E "^$$v=" .env 2>/dev/null | head -1 | cut -d= -f2-); \
		for ph in $(PLACEHOLDERS); do \
			if [ "$$valor" = "$$ph" ]; then valor=""; fi; \
		done; \
		test -n "$$valor" || { echo "ERROR: $$v sin configurar en .env. Ejecuta 'make install'."; exit 1; }; \
	done
	@for s in $(SECRETS); do \
		test -f $$s || { echo "ERROR: falta $$s. Ejecuta 'make install'."; exit 1; }; \
		test -s $$s || { echo "ERROR: $$s está vacío. Ejecuta 'make install'."; exit 1; }; \
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

test: check-config ## Ejecución única en simulación y verbosa (no modifica nada)
	@echo "Ejecución de prueba: DRY_RUN=true, no se escribe ni se borra nada."
	@echo ""
	$(COMPOSE) run --rm \
		-e RUN_ONCE=true \
		-e DRY_RUN=true \
		-e VERBOSE=true \
		$(SERVICE)

sync-once: check-config ## Una única sincronización REAL (sin simulación)
	@echo "ATENCIÓN: sincronización real, con borrado en origen si DELETE_SOURCE=true."
	@printf "¿Continuar? [s/N] " && read r && [ "$$r" = "s" ]
	$(COMPOSE) run --rm -e RUN_ONCE=true -e VERBOSE=true $(SERVICE)

logs: ## Sigue el log del contenedor
	$(COMPOSE) logs -f

status: ## Estado del contenedor y tamaño de los logs
	@$(COMPOSE) ps
	@echo ""
	@if [ -d logs ]; then du -sh logs 2>/dev/null; ls -la logs/ 2>/dev/null; else echo "(aún no hay logs)"; fi

shell: ## Abre una shell dentro del contenedor
	$(COMPOSE) exec $(SERVICE) /bin/bash

clean: ## Elimina contenedor, imagen y logs (conserva .env y contraseñas)
	@printf "Se borrarán contenedor, imagen y logs. ¿Continuar? [s/N] " && read r && [ "$$r" = "s" ]
	$(COMPOSE) down --rmi local -v
	rm -rf logs
	@echo "Limpiado. .env y los ficheros de contraseña se han conservado."
