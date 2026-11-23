-- =========================================================================
-- TRIGGERS - MÓDULO DE TESORERÍA Y CUENTAS POR PAGAR
-- Cada CREATE TRIGGER va precedido de DROP TRIGGER IF EXISTS: el archivo se
-- puede ejecutar varias veces (antes fallaba con "ya existe" y algunos
-- triggers quedaban sin crear).
-- =========================================================================
-- =========================================================================
-- LIMPIEZA DE VERSIONES ANTERIORES
-- Borra las funciones de trigger de este archivo y las obsoletas.
-- CASCADE elimina también sus triggers; el resto del archivo los vuelve a crear.
--   fun_val_a_pagar_archivo_plano: val_a_pagar lo asigna fun_insert_det_archivo_plano.
--   fun_marcar_cuotas_pagadas: cada cuota se marca pagada con fun_aplicar_pago_aprobado.
-- =========================================================================
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS fn
               FROM pg_proc
              WHERE proname IN ('fun_val_a_pagar_archivo_plano',
                                'fun_marcar_cuotas_pagadas',
                                'fun_monto_disponible_caja_menor',
                                'fun_fecha_cierre_caja_menor',
                                'fun_fecha_movimiento_caja_menor',
                                'fun_actualizar_disponible_caja_menor',
                                'fun_saldo_factura',
                                'fun_generar_cuotas_factura',
                                'fun_calcular_total_cronograma',
                                'fun_val_a_pagar_cronograma',
                                'fun_validar_fecha_cronograma',
                                'fun_fecha_generacion_archivo',
                                'fun_actualizar_saldo_factura',
                                'fun_actualizar_saldo_proveedor',
                                'fun_bloquear_nomina_enviada') LOOP
        EXECUTE 'DROP FUNCTION ' || r.fn || ' CASCADE';
    END LOOP;
END $$;
-- =========================================================================
-- 1. tab_enc_caja_menor
-- =========================================================================

-- 1.1 Al insertar una caja menor, monto_disponible = monto_asignado
CREATE OR REPLACE FUNCTION fun_monto_disponible_caja_menor() RETURNS TRIGGER AS 
$BODY$
BEGIN
    NEW.monto_disponible := NEW.monto_asignado;
    RETURN NEW;
END;
$BODY$ 
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_monto_disponible_caja_menor ON tab_enc_caja_menor;
CREATE TRIGGER trg_monto_disponible_caja_menor BEFORE INSERT ON tab_enc_caja_menor
FOR EACH ROW EXECUTE FUNCTION fun_monto_disponible_caja_menor();


-- 1.2 Al cerrar la caja (ind_estado_caja_m: TRUE -> FALSE), asignar fecha_cierre

CREATE OR REPLACE FUNCTION fun_fecha_cierre_caja_menor() RETURNS TRIGGER AS 
$BODY$
BEGIN
    IF OLD.ind_estado_caja_m = TRUE AND NEW.ind_estado_caja_m = FALSE THEN
        NEW.fecha_cierre := CURRENT_DATE;
    END IF;
    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_fecha_cierre_caja_menor ON tab_enc_caja_menor;
CREATE TRIGGER trg_fecha_cierre_caja_menor BEFORE UPDATE ON tab_enc_caja_menor
FOR EACH ROW WHEN (OLD.ind_estado_caja_m IS DISTINCT FROM NEW.ind_estado_caja_m)
EXECUTE FUNCTION fun_fecha_cierre_caja_menor();

-- =========================================================================
-- 2. tab_det_caja_menor
-- =========================================================================

-- 2.1 Forzar fecha_movimiento = CURRENT_DATE siempre (ignora lo que envíe el usuario)
CREATE OR REPLACE FUNCTION fun_fecha_movimiento_caja_menor() RETURNS TRIGGER AS 
$BODY$
BEGIN
    NEW.fecha_movimiento := CURRENT_DATE;
    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_fecha_movimiento_caja_menor ON tab_det_caja_menor;
CREATE TRIGGER trg_fecha_movimiento_caja_menor BEFORE INSERT ON tab_det_caja_menor
FOR EACH ROW EXECUTE FUNCTION fun_fecha_movimiento_caja_menor();


-- 2.2 Descontar monto_disponible SOLO cuando el movimiento pasa a Aprobado (1 -> 2)
--     y reponerlo si pasa a Reembolsado (2 -> 3).
CREATE OR REPLACE FUNCTION fun_actualizar_disponible_caja_menor() RETURNS TRIGGER AS
$BODY$
BEGIN
    -- Pasa de Pendiente(1) a Aprobado(2): se descuenta del disponible
    IF OLD.ind_estado = 1 AND NEW.ind_estado = 2 THEN
        UPDATE tab_enc_caja_menor
        SET monto_disponible = monto_disponible - NEW.val_movimiento
        WHERE id_caja_menor = NEW.id_caja_menor;

    -- Pasa de Aprobado(2) a Reembolsado(3): el dinero vuelve a la caja
    ELSIF OLD.ind_estado = 2 AND NEW.ind_estado = 3 THEN
        UPDATE tab_enc_caja_menor
        SET monto_disponible = monto_disponible + NEW.val_movimiento
        WHERE id_caja_menor = NEW.id_caja_menor;
    END IF;
-----------------------------------------------------------------------------
	-- PENDIENTE
	-- AGREGAR EL VALOR MÍNIMO DE REEMBOLSO DE PARÁMETROS DE TESORERÍA
-----------------------------------------------------------------------------	
    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_actualizar_disponible_caja_menor ON tab_det_caja_menor;
CREATE TRIGGER trg_actualizar_disponible_caja_menor AFTER UPDATE ON tab_det_caja_menor
FOR EACH ROW WHEN (OLD.ind_estado IS DISTINCT FROM NEW.ind_estado)
EXECUTE FUNCTION fun_actualizar_disponible_caja_menor();

-- NOTA: esta función no valida que monto_disponible no quede negativo.
-- Si quieres bloquear la aprobación cuando no hay fondos suficientes,
-- se puede agregar una validación adicional antes del UPDATE (lanzando
-- una excepción con RAISE EXCEPTION). Lo dejo fuera por ahora porque no
-- lo mencionaste como requisito, pero es algo a considerar.

-- =========================================================================
-- 3. tab_cuentasxpagar
-- =========================================================================

-- 3.1 Al insertar una factura, val_saldo = val_factura
CREATE OR REPLACE FUNCTION fun_saldo_factura() RETURNS TRIGGER AS
$BODY$
BEGIN
    NEW.val_saldo := NEW.val_factura;
    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_saldo_factura ON tab_cuentasxpagar;
CREATE TRIGGER trg_saldo_factura BEFORE INSERT ON tab_cuentasxpagar FOR EACH ROW
EXECUTE FUNCTION fun_saldo_factura();

-- =========================================================================
-- 4. tab_cuotasxfactura
-- =========================================================================

-- 4.1 Al insertar una factura, generar automáticamente sus N cuotas
--     (1 mes de separación entre cada cuota, a partir de fec_vencimiento)
--     Reparte val_factura entre num_cuotas; ajusta la última cuota para
--     que la suma cuadre exacto si la división no es entera.
CREATE OR REPLACE FUNCTION fun_generar_cuotas_factura() RETURNS TRIGGER AS
$BODY$
DECLARE
    wwvalor_base   tab_cuotasxfactura.val_cuota%TYPE;          -- (cálculo) valor de cada cuota
    wwsuma_parcial tab_cuotasxfactura.val_cuota%TYPE := 0;     -- (cálculo) suma de las cuotas ya creadas
    i              INT;
BEGIN
    wwvalor_base := TRUNC(NEW.val_factura / NEW.num_cuotas);

    FOR i IN 1..NEW.num_cuotas LOOP
        IF i < NEW.num_cuotas THEN
            INSERT INTO tab_cuotasxfactura(id_factura, id_cuota, fec_vencimiento, val_cuota)
            VALUES (
                NEW.id_factura,
                i,
                NEW.fec_vencimiento + ((i - 1) * INTERVAL '1 month'),
                wwvalor_base
            );
            wwsuma_parcial := wwsuma_parcial + wwvalor_base;
        ELSE
            -- última cuota: se ajusta para que la suma total sea exacta
            INSERT INTO tab_cuotasxfactura(id_factura, id_cuota, fec_vencimiento, val_cuota)
            VALUES (
                NEW.id_factura,
                i,
                NEW.fec_vencimiento + ((i - 1) * INTERVAL '1 month'),
                NEW.val_factura - wwsuma_parcial
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_generar_cuotas_factura ON tab_cuentasxpagar;
CREATE TRIGGER trg_generar_cuotas_factura AFTER INSERT ON tab_cuentasxpagar FOR EACH ROW
EXECUTE FUNCTION fun_generar_cuotas_factura();

-- NOTA IMPORTANTE: esta función usa NEW.fec_vencimiento como ancla para la
-- primera cuota. Revisa si esto es lo que quieres, porque fec_vencimiento
-- en tab_cuentasxpagar tiene el CHECK (fec_vencimiento > fec_emision), es
-- decir, representa el vencimiento de TODA la factura, no necesariamente
-- el de la primera cuota. Si prefieres anclar desde fec_emision en su lugar,
-- solo cambia esa referencia dentro del INSERT.

-- =========================================================================
-- 5. tab_enc_cronopagos
-- =========================================================================

-- 5.1 Recalcular total_a_pagar sumando el detalle (tab_det_cronopagos)
--     Se dispara desde el DETALLE, no desde el encabezado, porque el valor
--     depende de filas que viven en otra tabla.
CREATE OR REPLACE FUNCTION fun_calcular_total_cronograma() RETURNS TRIGGER AS
$BODY$
DECLARE
    wwid_cronograma tab_enc_cronopagos.id_cronograma%TYPE;
BEGIN
    wwid_cronograma := COALESCE(NEW.id_cronograma, OLD.id_cronograma);

    UPDATE tab_enc_cronopagos
    SET total_a_pagar = (
        SELECT COALESCE(SUM(val_a_pagar), 0)
        FROM tab_det_cronopagos
        WHERE id_cronograma = wwid_cronograma
    )
    WHERE id_cronograma = wwid_cronograma;

    RETURN NULL; -- trigger AFTER, el valor de retorno se ignora
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_calcular_total_cronograma ON tab_det_cronopagos;
CREATE TRIGGER trg_calcular_total_cronograma AFTER INSERT OR UPDATE OR DELETE ON tab_det_cronopagos
FOR EACH ROW EXECUTE FUNCTION fun_calcular_total_cronograma();


-- =========================================================================
-- 6. tab_det_cronopagos
-- =========================================================================

-- 6.1 fun_val_a_pagar_cronograma vuelve a su versión original
--     (solo trae val_a_pagar desde la cuota; sin validar fechas)
CREATE OR REPLACE FUNCTION fun_val_a_pagar_cronograma() RETURNS TRIGGER AS
$BODY$
BEGIN
    SELECT val_cuota
    INTO NEW.val_a_pagar
    FROM tab_cuotasxfactura
    WHERE id_factura = NEW.id_factura
      AND id_cuota   = NEW.id_cuota;
 
    IF NEW.val_a_pagar IS NULL THEN
        RAISE EXCEPTION 'No existe la cuota % de la factura % en tab_cuotasxfactura', NEW.id_cuota, NEW.id_factura;
    END IF;
 
    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_val_a_pagar_cronograma ON tab_det_cronopagos;
CREATE TRIGGER trg_val_a_pagar_cronograma BEFORE INSERT ON tab_det_cronopagos FOR EACH ROW
EXECUTE FUNCTION fun_val_a_pagar_cronograma();

-- =========================================================================
-- VALIDAR LA FECHA DE PROGRAMACIÓN DE UN CRONOGRAMA DE PAGOS
-- =========================================================================
-- Reglas:
--   1) fec_programacion debe caer en uno de los tres días de pago definidos
--      en tab_pmtros_tescxp (fec_diapago1..3: 1 = lunes ... 6 = sábado).
--   2) fec_programacion no puede ser un festivo activo de tab_festivos.
--
-- Se implementa como trigger BEFORE INSERT OR UPDATE para que aplique tanto
-- a fun_insert_enc_cronopagos como a fun_update_enc_cronopagos sin tener que
-- tocar esas funciones. El RAISE del trigger lo captura el EXCEPTION de la
-- función que hizo el INSERT/UPDATE y llega a PHP como mensaje normal.
--
-- EXTRACT(ISODOW ...) devuelve 1 = lunes ... 7 = domingo, que coincide con
-- la numeración usada en tab_pmtros_tescxp.
-- =========================================================================

-- 6.2 fun_validar_fecha_cronograma

CREATE OR REPLACE FUNCTION fun_validar_fecha_cronograma() RETURNS TRIGGER AS
$BODY$
DECLARE
    wdia            INTEGER;
    wdia1           tab_pmtros_tescxp.fec_diapago1%TYPE;
    wdia2           tab_pmtros_tescxp.fec_diapago2%TYPE;
    wdia3           tab_pmtros_tescxp.fec_diapago3%TYPE;
    wnom_festivo    tab_festivos.nom_festivo%TYPE;
    wnom_dia        VARCHAR(10);
BEGIN
    -- En un UPDATE que no cambia la fecha (ej. solo se renombra el cronograma)
    -- no se revalida: si después se creó un festivo en esa fecha o cambiaron
    -- los parámetros, el cronograma viejo se puede seguir editando.
    IF TG_OP = 'UPDATE' AND NEW.fec_programacion = OLD.fec_programacion THEN
        RETURN NEW;
    END IF;

    IF NEW.fec_programacion IS NULL THEN
        RAISE EXCEPTION 'La fecha de programación no puede ser nula.';
    END IF;

-- TRAER LOS DÍAS DE PAGO CONFIGURADOS
    SELECT fec_diapago1, fec_diapago2, fec_diapago3
      INTO wdia1, wdia2, wdia3
      FROM tab_pmtros_tescxp
     WHERE ind_borrado = FALSE
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay días de pago configurados en Parámetros de Tesorería.';
    END IF;

-- VALIDAR QUE LA FECHA CAIGA EN UN DÍA DE PAGO
    wdia := EXTRACT(ISODOW FROM NEW.fec_programacion)::INTEGER;

    IF  wdia IS DISTINCT FROM wdia1
    AND wdia IS DISTINCT FROM wdia2
    AND wdia IS DISTINCT FROM wdia3 THEN
        wnom_dia := CASE wdia
                        WHEN 1 THEN 'lunes'
                        WHEN 2 THEN 'martes'
                        WHEN 3 THEN 'miércoles'
                        WHEN 4 THEN 'jueves'
                        WHEN 5 THEN 'viernes'
                        WHEN 6 THEN 'sábado'
                        ELSE        'domingo'
                    END;
        RAISE EXCEPTION 'La fecha % cae en %, que no es un día de pago configurado en Parámetros de Tesorería.',
            TO_CHAR(NEW.fec_programacion, 'DD/MM/YYYY'), wnom_dia;
    END IF;

-- VALIDAR QUE LA FECHA NO SEA FESTIVO
    SELECT nom_festivo
      INTO wnom_festivo
      FROM tab_festivos
     WHERE fecha       = NEW.fec_programacion
       AND ind_borrado = FALSE
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'La fecha % es festivo (%). Elija otro día de pago.',
            TO_CHAR(NEW.fec_programacion, 'DD/MM/YYYY'), wnom_festivo;
    END IF;

    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_validar_fecha_cronograma ON tab_enc_cronopagos;
CREATE TRIGGER trg_validar_fecha_cronograma
BEFORE INSERT OR UPDATE OF fec_programacion ON tab_enc_cronopagos
FOR EACH ROW EXECUTE FUNCTION fun_validar_fecha_cronograma();

-- =========================================================================
-- 7. tab_enc_archivo_plano
-- =========================================================================

-- 7.1 Al generar el archivo (ind_generado: FALSE -> TRUE), asignar fec_generacion
CREATE OR REPLACE FUNCTION fun_fecha_generacion_archivo() RETURNS TRIGGER AS
$BODY$
BEGIN
    IF OLD.ind_generado = FALSE AND NEW.ind_generado = TRUE THEN
        NEW.fec_generacion := CURRENT_DATE;
    END IF;
    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_fecha_generacion_archivo ON tab_enc_archivo_plano;
CREATE TRIGGER trg_fecha_generacion_archivo BEFORE UPDATE ON tab_enc_archivo_plano
FOR EACH ROW WHEN (OLD.ind_generado IS DISTINCT FROM NEW.ind_generado)
EXECUTE FUNCTION fun_fecha_generacion_archivo();


-- =========================================================================
-- 8. tab_det_archivo_plano 
-- =========================================================================

-- 8.1 Ya no hay trigger aquí: val_a_pagar lo asigna fun_insert_det_archivo_plano
--     con el valor de la cuota (tab_cuotasxfactura.val_cuota). Se borra el
--     trigger anterior si existe.
DROP TRIGGER IF EXISTS trg_val_a_pagar_archivo_plano ON tab_det_archivo_plano;
DROP FUNCTION IF EXISTS fun_val_a_pagar_archivo_plano();


-- =========================================================================
-- 9. CADENA DE PAGO: cronograma pagado -> cuotas pagadas -> saldo factura
-- =========================================================================

-- 9.1 SE ELIMINA trg_marcar_cuotas_pagadas.
--     Antes, al cerrar el cronograma se marcaban como pagadas TODAS sus cuotas.
--     Ahora el cronograma se cierra cuando el banco ya respondió todas sus
--     cuotas, aunque algunas vengan RECHAZADAS; si el trigger siguiera, esas
--     cuotas rechazadas quedarían pagadas sin haberse pagado. Cada cuota se
--     marca pagada solo con su pago APROBADO (fun_aplicar_pago_aprobado).
DROP TRIGGER IF EXISTS trg_marcar_cuotas_pagadas ON tab_enc_cronopagos;
DROP FUNCTION IF EXISTS fun_marcar_cuotas_pagadas();


-- 9.2 Cuando una cuota pasa a pagada (ind_pagada: FALSE -> TRUE), descontar
--     su valor del saldo de la factura, y si el saldo llega a 0, marcar la
--     factura como pagada (ind_estado = TRUE).
CREATE OR REPLACE FUNCTION fun_actualizar_saldo_factura() RETURNS TRIGGER AS
$BODY$
BEGIN
    IF OLD.ind_pagada = FALSE AND NEW.ind_pagada = TRUE THEN
        UPDATE tab_cuentasxpagar
        SET val_saldo  = val_saldo - NEW.val_cuota,
            ind_estado = CASE WHEN (val_saldo - NEW.val_cuota) <= 0 THEN TRUE ELSE ind_estado END
        WHERE id_factura = NEW.id_factura;
    END IF;
    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_actualizar_saldo_factura ON tab_cuotasxfactura;
CREATE TRIGGER trg_actualizar_saldo_factura AFTER UPDATE ON tab_cuotasxfactura
FOR EACH ROW WHEN (OLD.ind_pagada IS DISTINCT FROM NEW.ind_pagada)
EXECUTE FUNCTION fun_actualizar_saldo_factura();

-- NOTA: las cuotas se marcan pagadas una por una desde fun_insert_pagos_cxp /
-- fun_update_pagos_cxp al aprobar el pago (fun_aplicar_pago_aprobado). El
-- cierre del cronograma (fun_cerrar_cronograma_procesado) ya no toca las
-- cuotas. Si se marca una cuota pagada a mano, 9.2 igual descuenta el saldo.

-- =========================================================================
-- 10. ACTUALIZAR SALDO PROVEEDOR: Saldo proveedor = saldo proveedor - valor del saldo de la factura
-- =========================================================================

-- 10 Cuando baja el saldo de una factura, descontar esa diferencia de la
--    deuda del proveedor (tab_proveedores.val_saldo_deuda).

CREATE OR REPLACE FUNCTION fun_actualizar_saldo_proveedor()
RETURNS TRIGGER AS
$BODY$
DECLARE
    wresta tab_cuentasxpagar.val_saldo%TYPE;   -- (cálculo) cuánto bajó el saldo
BEGIN

    -- Determinar cuánto disminuyó el saldo de la cuenta
    wresta := OLD.val_saldo - NEW.val_saldo;

    -- Actualizar la deuda del proveedor
    UPDATE tab_proveedores
    SET    val_saldo_deuda = val_saldo_deuda - wresta
    WHERE  id_proveedor = NEW.id_proveedor;

    RETURN NEW;

END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_actualizar_saldo_proveedor ON tab_cuentasxpagar;
CREATE TRIGGER trg_actualizar_saldo_proveedor
AFTER UPDATE OF val_saldo ON tab_cuentasxpagar
FOR EACH ROW
EXECUTE FUNCTION fun_actualizar_saldo_proveedor();


--------------------------------------------------------------------------------------------------------------------------------------
-- 11. tab_nomina (integración con Nómina): NÓMINA ENVIADA O PAGADA NO SE PUEDE CAMBIAR
--------------------------------------------------------------------------------------------------------------------------------------
-- Si Nómina vuelve a liquidar después de enviar, el archivo plano ya tiene
-- el valor viejo. Mientras esté enviada (1) o pagada (2) no se puede cambiar
-- el valor ni borrar el registro; si alguna vez fue al banco (1, 2 o 3) no se
-- puede eliminar (la línea del archivo plano apunta a él). Si hay que
-- corregir algo, Tesorería devuelve el archivo (Archivo Plano → Devolver a
-- Nómina) y Nómina vuelve a liquidar.
-- ind_cerrado e ind_pagado SÍ se pueden cambiar: los maneja Nómina
-- (fun_marcar_nomina_pagada).
CREATE OR REPLACE FUNCTION fun_bloquear_nomina_enviada() RETURNS TRIGGER AS
$BODY$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.estado_pago IN (1, 2, 3) THEN
            RAISE EXCEPTION 'La nómina de % (%-%, periodo %) ya fue % y no se puede volver a liquidar.%',
                OLD.id_empleado, OLD.ano_nomina, OLD.mes_nomina, OLD.val_periodo,
                CASE OLD.estado_pago WHEN 1 THEN 'enviada a Tesorería'
                                     WHEN 2 THEN 'pagada'
                                     ELSE 'enviada al banco (rechazada)' END,
                CASE OLD.estado_pago WHEN 1 THEN ' Pida a Tesorería que la devuelva.'
                                     WHEN 3 THEN ' Corrija la cuenta en Empleados y reenvíela a Tesorería.'
                                     ELSE '' END;
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.estado_pago IN (1, 2) AND (
           NEW.val_neto        IS DISTINCT FROM OLD.val_neto
        OR NEW.tot_devengado   IS DISTINCT FROM OLD.tot_devengado
        OR NEW.tot_deducido    IS DISTINCT FROM OLD.tot_deducido
        OR NEW.ind_borrado     IS DISTINCT FROM OLD.ind_borrado
        OR NEW.id_empleado     IS DISTINCT FROM OLD.id_empleado
        OR NEW.ano_nomina      IS DISTINCT FROM OLD.ano_nomina
        OR NEW.mes_nomina      IS DISTINCT FROM OLD.mes_nomina
        OR NEW.val_periodo     IS DISTINCT FROM OLD.val_periodo) THEN
        RAISE EXCEPTION 'La nómina de % (%-%, periodo %) ya fue % y no se puede modificar.%',
            OLD.id_empleado, OLD.ano_nomina, OLD.mes_nomina, OLD.val_periodo,
            CASE OLD.estado_pago WHEN 1 THEN 'enviada a Tesorería' ELSE 'pagada' END,
            CASE OLD.estado_pago WHEN 1 THEN ' Pida a Tesorería que la devuelva.' ELSE '' END;
    END IF;

    RETURN NEW;
END;
$BODY$
LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS trg_bloquear_nomina_enviada ON tab_nomina;
CREATE TRIGGER trg_bloquear_nomina_enviada BEFORE UPDATE OR DELETE ON tab_nomina
FOR EACH ROW EXECUTE FUNCTION fun_bloquear_nomina_enviada();
