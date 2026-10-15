-- ═══════════════════════════════════════════════════════════════════
-- AppOrganizadora · esquema v1 (V2 del sistema, sin Telegram)
-- El migrador ejecuta este fichero en una transacción y fija user_version = 1.
--
-- Convención de fechas del SERVIDOR: texto ISO 8601 UTC con milisegundos y 'Z'
--   2026-10-15T18:00:00.123Z
-- Es el mismo formato que strftime('%Y-%m-%dT%H:%M:%fZ') y que iso_utc() en Python.
-- Formato fijo => la comparación de texto equivale a la cronológica.
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE mensajes (
    -- UUID generado por la app (clave de idempotencia), canónico y en minúsculas
    id                TEXT    PRIMARY KEY
                              CHECK (length(id) = 36 AND id = lower(id)),

    texto             TEXT    NOT NULL
                              CHECK (length(texto) BETWEEN 1 AND 2000),

    estado            TEXT    NOT NULL DEFAULT 'PENDIENTE'
                              CHECK (estado IN ('PENDIENTE', 'PROCESANDO', 'INTERPRETADO',
                                                'EJECUTANDO', 'COMPLETADO', 'ERROR')),

    -- Reloj del servidor (UTC, formato fijo: se usa para ordenar la cola)
    fecha_recepcion   TEXT    NOT NULL
                              CHECK (fecha_recepcion GLOB '????-??-??T??:??:??.???Z'),

    -- Reloj del móvil, con su offset (referencia para "mañana", "el viernes"...)
    -- No se compara en SQL, por eso admite cualquier ISO 8601 válido.
    fecha_dictado     TEXT,

    zona_horaria      TEXT    NOT NULL DEFAULT 'Europe/Madrid'
                              CHECK (length(zona_horaria) BETWEEN 1 AND 64),

    -- Resultado de la fase NLP
    intencion         TEXT,
    resultado_json    TEXT    CHECK (resultado_json IS NULL OR json_valid(resultado_json)),

    -- Lo que verá la app (título, fecha, enlace, avisos...)
    respuesta_json    TEXT    CHECK (respuesta_json IS NULL OR json_valid(respuesta_json)),

    error             TEXT,

    -- Intentos de la fase actual (se reinicia al pasar a INTERPRETADO)
    intentos          INTEGER NOT NULL DEFAULT 0 CHECK (intentos >= 0),

    siguiente_intento TEXT    CHECK (siguiente_intento IS NULL
                                     OR siguiente_intento GLOB '????-??-??T??:??:??.???Z'),

    -- Resultado en Google
    external_id       TEXT,
    external_link     TEXT,

    creado_en         TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    actualizado_en    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

-- La consulta de "reclamar" filtra por estado + siguiente_intento y ordena por recepción
CREATE INDEX ix_mensajes_cola ON mensajes (estado, siguiente_intento, fecha_recepcion);

-- actualizado_en automático. El WHEN evita la recursión: el UPDATE interno
-- cambia actualizado_en, así que la condición ya no se cumple.
CREATE TRIGGER trg_mensajes_actualizado
AFTER UPDATE ON mensajes
FOR EACH ROW
WHEN NEW.actualizado_en = OLD.actualizado_en
BEGIN
    UPDATE mensajes
    SET actualizado_en = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    WHERE id = NEW.id;
END;
