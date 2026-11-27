--------------------------------------------------------------------------------------------------------------------------------------
-- LIMPIEZA DE VERSIONES ANTERIORES
-- Borra las funciones de este archivo que cambiaron de parámetros o que ya no
-- existen (motivos de rechazo). CREATE OR REPLACE no reemplaza una función
-- cuya firma cambió: crearía una segunda versión al lado de la vieja.
--------------------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS fn
               FROM pg_proc
              WHERE proname IN ('fun_insert_pmtros_tescxp',
                                'fun_insert_festivos',
                                'fun_insert_enc_caja_menor',
                                'fun_insert_det_caja_menor',
                                'fun_insert_ctas_empresa',
                                'fun_insert_bancoxprov',
                                'fun_insert_cuentasxpagar',
                                'fun_insert_enc_cronopagos',
                                'fun_insert_det_cronopagos',
                                'fun_insert_enc_archivo_plano',
                                'fun_insert_det_archivo_plano',
                                'fun_insert_codigos_respuesta_banco',
                                'fun_insert_bancos',
                                'fun_cerrar_cronograma_procesado',
                                'fun_aplicar_pago_aprobado',
                                'fun_insert_pagos_cxp',
                                'fun_tipo_archivo_plano',
                                'fun_proxima_fecha_pago',
                                'fun_enviar_nomina_tesoreria',
                                'fun_aplicar_respuesta_nomina',
                                'fun_insert_pagos_nomina',
                                'fun_enviar_inversiones_tesoreria',
                                'fun_aplicar_respuesta_inversion',
                                'fun_insert_pagos_inversion',
                                'fun_usuario_erp',
                                'fun_id_modulo_tesoreria',
                                'fun_es_lider_tesoreria',
                                'fun_registrar_descarga_archivo',
                                'fun_insert_inconsistencia_respuesta',
                                'fun_validar_total_respuesta',
                                'fun_crear_archivo_plano',
                                'fun_crear_cronograma') LOOP
        EXECUTE 'DROP FUNCTION ' || r.fn;
    END LOOP;
END $$;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE PARÁMETROS DE TESORERÍA Y CXP
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_pmtros_tescxp (wid_empresa         tab_pmtros_tescxp.id_empresa%TYPE,
                                                     wfec_diapago1       tab_pmtros_tescxp.fec_diapago1%TYPE,
                                                     wfec_diapago2       tab_pmtros_tescxp.fec_diapago2%TYPE,
                                                     wfec_diapago3       tab_pmtros_tescxp.fec_diapago3%TYPE,
                                                     wval_min_reembolso  tab_pmtros_tescxp.val_min_reembolso%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID DE LA EMPRESA NO SEA NULO
    IF wid_empresa IS NULL THEN
        RAISE EXCEPTION 'El ID de la empresa no puede ser nulo.';
    END IF;

-- VALIDAR QUE LOS DÍAS DE PAGO NO SEAN NULOS
    IF wfec_diapago1 IS NULL THEN
        RAISE EXCEPTION 'El día de pago 1 no puede ser nulo.';
    END IF;

    IF wfec_diapago2 IS NULL THEN
        RAISE EXCEPTION 'El día de pago 2 no puede ser nulo.';
    END IF;

    IF wfec_diapago3 IS NULL THEN
        RAISE EXCEPTION 'El día de pago 3 no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL VALOR MÍNIMO DE REEMBOLSO NO SEA NULO
    IF wval_min_reembolso IS NULL THEN
        RAISE EXCEPTION 'El valor mínimo de reembolso no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL ID DE LA EMPRESA EXISTA EN PARÁMETROS GENERALES
    IF NOT EXISTS (SELECT 1 FROM tab_pmtros_grales WHERE id_empresa = wid_empresa) THEN
        RAISE EXCEPTION 'La empresa % no existe en los parámetros.', wid_empresa;
    END IF;

-- VALIDAR QUE EL ID DE LA EMPRESA ESTÉ ENTRE 6 Y 10 CARACTERES
    IF LENGTH(wid_empresa) < 6 OR LENGTH(wid_empresa) > 10 THEN
        RAISE EXCEPTION 'El ID de la empresa debe tener entre 6 y 10 caracteres.';
    END IF;

-- VALIDAR QUE LOS DÍAS DE PAGO NO SEAN IGUALES
    IF wfec_diapago1 = wfec_diapago2 OR wfec_diapago1 = wfec_diapago3 OR wfec_diapago2 = wfec_diapago3 THEN
        RAISE EXCEPTION 'Los días de pago no pueden ser iguales entre sí.';
    END IF;

-- VALIDAR QUE LOS DÍAS DE PAGO ESTÉN ENTRE 1 Y 6 (lunes a sábado)
    IF wfec_diapago1 < 1 OR wfec_diapago1 > 6 THEN
        RAISE EXCEPTION 'El día de pago 1 debe estar entre 1 y 6.';
    END IF;

    IF wfec_diapago2 < 1 OR wfec_diapago2 > 6 THEN
        RAISE EXCEPTION 'El día de pago 2 debe estar entre 1 y 6.';
    END IF;

    IF wfec_diapago3 < 1 OR wfec_diapago3 > 6 THEN
        RAISE EXCEPTION 'El día de pago 3 debe estar entre 1 y 6.';
    END IF;

-- VALIDAR QUE EL VALOR MÍNIMO DE REEMBOLSO ESTÉ ENTRE 0 Y 99999999
    IF wval_min_reembolso < 0 OR wval_min_reembolso > 99999999 THEN
        RAISE EXCEPTION 'El valor mínimo de reembolso debe estar entre 0 y 99.999.999.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_pmtros_tescxp
    INSERT INTO tab_pmtros_tescxp (id_empresa, fec_diapago1, fec_diapago2, fec_diapago3, val_min_reembolso)
    VALUES (wid_empresa, wfec_diapago1, wfec_diapago2, wfec_diapago3, wval_min_reembolso);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE FESTIVOS
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_festivos (wfecha          tab_festivos.fecha%TYPE,
                                                wnom_festivo    tab_festivos.nom_festivo%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wid_festivo tab_festivos.id_festivo%TYPE;

BEGIN

-- VALIDAR QUE LA FECHA NO SEA NULA
    IF wfecha IS NULL THEN
        RAISE EXCEPTION 'La fecha del festivo no puede ser nula.';
    END IF;

-- VALIDAR QUE EL NOMBRE DEL FESTIVO NO SEA NULO
    IF wnom_festivo IS NULL THEN
        RAISE EXCEPTION 'El nombre del festivo no puede ser nulo.';
    END IF;

-- VALIDAR QUE LA FECHA NO SEA MENOR A LA ACTUAL
    IF wfecha < CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha del festivo no puede ser anterior a la fecha actual.';
    END IF;

-- VALIDAR QUE EL NOMBRE NO SEA VACÍO
    IF wnom_festivo = '' THEN
        RAISE EXCEPTION 'El nombre del festivo no puede estar vacío.';
    END IF;

-- VALIDAR QUE EL NOMBRE ESTÉ ENTRE 3 Y 50 CARACTERES
    IF LENGTH(wnom_festivo) < 3 OR LENGTH(wnom_festivo) > 50 THEN
        RAISE EXCEPTION 'El nombre del festivo debe tener entre 3 y 50 caracteres.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_festivos

    SELECT COALESCE(MAX(id_festivo), 0) + 1 INTO wid_festivo
    FROM tab_festivos;

    INSERT INTO tab_festivos (id_festivo, fecha, nom_festivo)
    VALUES                   (wid_festivo,wfecha,wnom_festivo);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE CAJA MENOR
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_enc_caja_menor (wnom_caja_menor         tab_enc_caja_menor.nom_caja_menor%TYPE,
                                                      wmonto_asignado         tab_enc_caja_menor.monto_asignado%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wid_caja_menor tab_enc_caja_menor.id_caja_menor%TYPE;

BEGIN

-- VALIDAR QUE EL NOMBRE DE LA CAJA MENOR NO SEA NULO
    IF wnom_caja_menor IS NULL THEN
        RAISE EXCEPTION 'El nombre de la caja menor no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL MONTO ASIGNADO NO SEA NULO
    IF wmonto_asignado IS NULL THEN
        RAISE EXCEPTION 'El monto asignado no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL NOMBRE NO SEA VACÍO
    IF wnom_caja_menor = '' THEN
        RAISE EXCEPTION 'El nombre de la caja menor no puede estar vacío.';
    END IF;

-- VALIDAR QUE EL NOMBRE ESTÉ ENTRE 3 Y 50 CARACTERES
    IF LENGTH(wnom_caja_menor) < 3 OR LENGTH(wnom_caja_menor) > 50 THEN
        RAISE EXCEPTION 'El nombre de la caja menor debe tener entre 3 y 50 caracteres.';
    END IF;

-- VALIDAR QUE EL MONTO ASIGNADO ESTÉ ENTRE 0 Y 99999999
    IF wmonto_asignado < 0 OR wmonto_asignado > 99999999 THEN
        RAISE EXCEPTION 'El monto asignado debe estar entre 0 y 99.999.999.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_enc_caja_menor

    SELECT COALESCE(MAX(id_caja_menor), 0) + 1 INTO wid_caja_menor
    FROM tab_enc_caja_menor;

    INSERT INTO tab_enc_caja_menor (id_caja_menor, nom_caja_menor, monto_asignado)
    VALUES                         (wid_caja_menor, wnom_caja_menor, wmonto_asignado);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE DETALLE DE CAJA MENOR
-- CORRECCIONES:
--   * Valida que la caja exista y que esté ACTIVA (antes permitía registrar en cajas cerradas).
--   * Bloquea la fila de la caja (FOR UPDATE) para que dos movimientos simultáneos
--     no pasen la validación de saldo con el mismo disponible.
--   * Si la caja no existía, wdisponible quedaba NULL y la validación de saldo se saltaba.
--   * La validación de largo del concepto decía "entre 1 y 200" pero exigía mínimo 3.
--   * La fecha no puede ser anterior al día de hoy (sí se permiten fechas futuras).
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_det_caja_menor (wid_caja_menor        tab_det_caja_menor.id_caja_menor%TYPE,
                                                      wconcepto             tab_det_caja_menor.concepto%TYPE,
                                                      wval_movimiento       tab_det_caja_menor.val_movimiento%TYPE,
                                                      wfecha_movimiento     tab_det_caja_menor.fecha_movimiento%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE
    wdisponible       tab_enc_caja_menor.monto_disponible%TYPE;
    wcaja_activa      tab_enc_caja_menor.ind_estado_caja_m%TYPE;
    wid_movimiento    tab_det_caja_menor.id_movimiento%TYPE;

BEGIN

-- VALIDAR QUE EL ID DE LA CAJA MENOR NO SEA NULO
    IF wid_caja_menor IS NULL THEN
        RAISE EXCEPTION 'El ID de la caja menor no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL CONCEPTO NO SEA NULO
    IF wconcepto IS NULL THEN
        RAISE EXCEPTION 'El concepto no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL VALOR DEL MOVIMIENTO NO SEA NULO
    IF wval_movimiento IS NULL THEN
        RAISE EXCEPTION 'El valor del movimiento no puede ser nulo.';
    END IF;

-- VALIDAR QUE LA FECHA DEL MOVIMIENTO NO SEA NULA
    IF wfecha_movimiento IS NULL THEN
        RAISE EXCEPTION 'La fecha del movimiento no puede ser nula.';
    END IF;

-- VALIDAR QUE LA CAJA EXISTA Y ESTÉ ACTIVA (SE BLOQUEA LA FILA HASTA TERMINAR LA TRANSACCIÓN)
    SELECT monto_disponible, ind_estado_caja_m
    INTO   wdisponible, wcaja_activa
    FROM   tab_enc_caja_menor
    WHERE  id_caja_menor = wid_caja_menor
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La caja menor % no existe.', wid_caja_menor;
    END IF;

    IF wcaja_activa IS NOT TRUE THEN
        RAISE EXCEPTION 'La caja menor % está cerrada y no admite nuevos movimientos.', wid_caja_menor;
    END IF;

-- VALIDAR QUE EL CONCEPTO NO SEA VACÍO
    IF TRIM(wconcepto) = '' THEN
        RAISE EXCEPTION 'El concepto no puede estar vacío.';
    END IF;

-- VALIDAR QUE EL CONCEPTO TENGA ENTRE 1 Y 200 CARACTERES
    IF LENGTH(wconcepto) < 1 OR LENGTH(wconcepto) > 200 THEN
        RAISE EXCEPTION 'El concepto debe tener entre 1 y 200 caracteres.';
    END IF;

-- VALIDAR QUE EL VALOR DEL MOVIMIENTO SEA MAYOR A 0 Y MENOR O IGUAL A 99999999
    IF wval_movimiento <= 0 OR wval_movimiento > 99999999 THEN
        RAISE EXCEPTION 'El valor del movimiento debe estar entre 1 y 99.999.999.';
    END IF;

-- VALIDAR QUE LA FECHA NO SEA ANTERIOR AL DÍA DE HOY (SE PERMITEN FECHAS FUTURAS)
    IF wfecha_movimiento < CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha del movimiento no puede ser anterior al día de hoy.';
    END IF;

-- VALIDAR QUE HAY SALDO SUFICIENTE EN LA CAJA MENOR
    IF wval_movimiento > COALESCE(wdisponible, 0) THEN
        RAISE EXCEPTION 'El valor del movimiento (%) supera el monto disponible en la caja menor (%).', wval_movimiento, COALESCE(wdisponible, 0);
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_det_caja_menor
    SELECT COALESCE(MAX(id_movimiento), 0) + 1 INTO wid_movimiento
    FROM tab_det_caja_menor;

    INSERT INTO tab_det_caja_menor (id_caja_menor, id_movimiento, concepto, val_movimiento, fecha_movimiento)
    VALUES                         (wid_caja_menor, wid_movimiento, wconcepto, wval_movimiento, wfecha_movimiento);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE CUENTAS DE LA EMPRESA
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_ctas_empresa (wid_empresa         tab_ctas_empresa.id_empresa%TYPE,
                                                    wcta_empresa        tab_ctas_empresa.cta_empresa%TYPE,
                                                    wid_banco           tab_ctas_empresa.id_banco%TYPE,
                                                    wind_tipocuenta     tab_ctas_empresa.ind_tipocuenta%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID DE LA EMPRESA NO SEA NULO
    IF wid_empresa IS NULL THEN
        RAISE EXCEPTION 'El ID de la empresa no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL NÚMERO DE CUENTA NO SEA NULO
    IF wcta_empresa IS NULL THEN
        RAISE EXCEPTION 'El número de cuenta de la empresa no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL ID DEL BANCO NO SEA NULO
    IF wid_banco IS NULL THEN
        RAISE EXCEPTION 'El ID del banco no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL INDICADOR DE TIPO DE CUENTA NO SEA NULO
    IF wind_tipocuenta IS NULL THEN
        RAISE EXCEPTION 'El indicador de tipo de cuenta no puede ser nulo.';
    END IF;

-- VALIDAR QUE LA EMPRESA EXISTA EN tab_pmtros_tescxp (FK)
    IF NOT EXISTS (SELECT 1 FROM tab_pmtros_tescxp WHERE id_empresa = wid_empresa) THEN
        RAISE EXCEPTION 'La empresa % no existe en los parámetros de tesorería.', wid_empresa;
    END IF;

-- VALIDAR QUE NO EXISTA YA ESA COMBINACIÓN EMPRESA + CUENTA (PK COMPUESTA)
    IF EXISTS (SELECT 1 FROM tab_ctas_empresa WHERE id_empresa = wid_empresa AND cta_empresa = wcta_empresa) THEN
        RAISE EXCEPTION 'La cuenta % ya está registrada para la empresa %.', wcta_empresa, wid_empresa;
    END IF;

-- VALIDAR QUE EL BANCO EXISTA
    IF NOT EXISTS (SELECT 1 FROM tab_bancos WHERE id_banco = wid_banco) THEN
        RAISE EXCEPTION 'El banco % no existe.', wid_banco;
    END IF;

-- VALIDAR QUE EL ID DE LA EMPRESA TENGA ENTRE 6 Y 10 CARACTERES
    IF LENGTH(wid_empresa) < 6 OR LENGTH(wid_empresa) > 10 THEN
        RAISE EXCEPTION 'El ID de la empresa debe tener entre 6 y 10 caracteres.';
    END IF;

-- VALIDAR QUE EL NÚMERO DE CUENTA TENGA ENTRE 10 Y 16 CARACTERES
    IF LENGTH(wcta_empresa) < 10 OR LENGTH(wcta_empresa) > 16 THEN
        RAISE EXCEPTION 'El número de cuenta de la empresa debe tener entre 10 y 16 caracteres.';
    END IF;

-- VALIDAR QUE EL ID DEL BANCO TENGA ENTRE 6 Y 10 CARACTERES
    IF LENGTH(wid_banco) < 6 OR LENGTH(wid_banco) > 10 THEN
        RAISE EXCEPTION 'El ID del banco debe tener entre 6 y 10 caracteres.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_ctas_empresa
    INSERT INTO tab_ctas_empresa (id_empresa, cta_empresa, id_banco, ind_tipocuenta)
    VALUES (wid_empresa, wcta_empresa, wid_banco, wind_tipocuenta);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE BANCOS POR PROVEEDORES
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_bancoxprov (wid_proveedor       tab_bancoxprov.id_proveedor%TYPE,
                                                  wcta_proveedor      tab_bancoxprov.cta_proveedor%TYPE,
                                                  wid_banco           tab_bancoxprov.id_banco%TYPE,
                                                  wind_tipocuenta     tab_bancoxprov.ind_tipocuenta%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID DEL PROVEEDOR NO SEA NULO
    IF wid_proveedor IS NULL THEN
        RAISE EXCEPTION 'El ID del proveedor no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL NÚMERO DE CUENTA NO SEA NULO
    IF wcta_proveedor IS NULL THEN
        RAISE EXCEPTION 'El número de cuenta del proveedor no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL ID DEL BANCO NO SEA NULO
    IF wid_banco IS NULL THEN
        RAISE EXCEPTION 'El ID del banco no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL INDICADOR DE TIPO DE CUENTA NO SEA NULO
    IF wind_tipocuenta IS NULL THEN
        RAISE EXCEPTION 'El indicador de tipo de cuenta no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL PROVEEDOR EXISTA
    IF NOT EXISTS (SELECT 1 FROM tab_proveedores WHERE id_proveedor = wid_proveedor) THEN
        RAISE EXCEPTION 'El proveedor % no existe.', wid_proveedor;
    END IF;

-- VALIDAR QUE EL BANCO EXISTA
    IF NOT EXISTS (SELECT 1 FROM tab_bancos WHERE id_banco = wid_banco) THEN
        RAISE EXCEPTION 'El banco % no existe.', wid_banco;
    END IF;

-- VALIDAR QUE NO EXISTA YA ESA COMBINACIÓN PROVEEDOR + CUENTA (PK COMPUESTA)
    IF EXISTS (SELECT 1 FROM tab_bancoxprov WHERE id_proveedor = wid_proveedor AND cta_proveedor = wcta_proveedor) THEN
        RAISE EXCEPTION 'La cuenta % ya está registrada para el proveedor %.', wcta_proveedor, wid_proveedor;
    END IF;

-- VALIDAR QUE EL ID DEL PROVEEDOR TENGA ENTRE 6 Y 10 CARACTERES
    IF LENGTH(wid_proveedor) < 6 OR LENGTH(wid_proveedor) > 10 THEN
        RAISE EXCEPTION 'El ID del proveedor debe tener entre 6 y 10 caracteres.';
    END IF;

-- VALIDAR QUE EL NÚMERO DE CUENTA TENGA ENTRE 10 Y 16 CARACTERES
    IF LENGTH(wcta_proveedor) < 10 OR LENGTH(wcta_proveedor) > 16 THEN
        RAISE EXCEPTION 'El número de cuenta del proveedor debe tener entre 10 y 16 caracteres.';
    END IF;

-- VALIDAR QUE EL ID DEL BANCO TENGA ENTRE 6 Y 10 CARACTERES
    IF LENGTH(wid_banco) < 6 OR LENGTH(wid_banco) > 10 THEN
        RAISE EXCEPTION 'El ID del banco debe tener entre 6 y 10 caracteres.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_bancoxprov
    INSERT INTO tab_bancoxprov (id_proveedor, cta_proveedor, id_banco, ind_tipocuenta)
    VALUES (wid_proveedor, wcta_proveedor, wid_banco, wind_tipocuenta);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE FACTURAS (actualizada: id_ordencompra opcional + validaciones cruzadas)
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_cuentasxpagar (wid_factura         tab_cuentasxpagar.id_factura%TYPE,
                                                     wid_proveedor       tab_cuentasxpagar.id_proveedor%TYPE,
                                                     wid_ordencompra     tab_cuentasxpagar.id_ordencompra%TYPE,
                                                     wfec_emision        tab_cuentasxpagar.fec_emision%TYPE,
                                                     wfec_vencimiento    tab_cuentasxpagar.fec_vencimiento%TYPE,
                                                     wval_factura        tab_cuentasxpagar.val_factura%TYPE,
                                                     wnum_cuotas         tab_cuentasxpagar.num_cuotas%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wordencompra_id_proveedor   tab_enc_ordcomp.id_proveedor%TYPE;
        wordencompra_ind_estado     tab_enc_ordcomp.ind_estado%TYPE;
        wordencompra_val_total      tab_enc_ordcomp.val_total%TYPE;
        wtotal_facturado            tab_cuentasxpagar.val_factura%TYPE;

BEGIN

-- VALIDAR QUE EL ID DE LA FACTURA NO SEA NULO
    IF wid_factura IS NULL THEN
        RAISE EXCEPTION 'El ID de la factura no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL ID DEL PROVEEDOR NO SEA NULO
    IF wid_proveedor IS NULL THEN
        RAISE EXCEPTION 'El ID del proveedor no puede ser nulo.';
    END IF;

-- VALIDAR QUE LA FECHA DE EMISIÓN NO SEA NULA
    IF wfec_emision IS NULL THEN
        RAISE EXCEPTION 'La fecha de emisión no puede ser nula.';
    END IF;

-- VALIDAR QUE LA FECHA DE VENCIMIENTO NO SEA NULA
    IF wfec_vencimiento IS NULL THEN
        RAISE EXCEPTION 'La fecha de vencimiento no puede ser nula.';
    END IF;

-- VALIDAR QUE EL VALOR DE LA FACTURA NO SEA NULO
    IF wval_factura IS NULL THEN
        RAISE EXCEPTION 'El valor de la factura no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL NÚMERO DE CUOTAS NO SEA NULO
    IF wnum_cuotas IS NULL THEN
        RAISE EXCEPTION 'El número de cuotas no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL ID DE LA FACTURA NO EXISTA
    IF EXISTS (SELECT 1 FROM tab_cuentasxpagar WHERE id_factura = wid_factura) THEN
        RAISE EXCEPTION 'El ID de la factura % ya existe.', wid_factura;
    END IF;

-- VALIDAR QUE EL ID DE LA FACTURA ESTÉ ENTRE 1 Y 99999999
    IF wid_factura < 1 OR wid_factura > 99999999 THEN
        RAISE EXCEPTION 'El ID de la factura debe estar entre 1 y 99.999.999.';
    END IF;

-- VALIDAR QUE EL PROVEEDOR EXISTA
    IF NOT EXISTS (SELECT 1 FROM tab_proveedores WHERE id_proveedor = wid_proveedor) THEN
        RAISE EXCEPTION 'El proveedor % no existe.', wid_proveedor;
    END IF;

-- VALIDAR LA ORDEN DE COMPRA (CAMPO OPCIONAL: puede llegar NULL desde el front)
    IF wid_ordencompra IS NOT NULL THEN

        -- VALIDAR QUE EL ID DE LA ORDEN DE COMPRA SEA MAYOR A 0
        IF wid_ordencompra <= 0 THEN
            RAISE EXCEPTION 'El ID de la orden de compra debe ser mayor a 0.';
        END IF;

        -- VALIDAR QUE LA ORDEN EXISTA Y TRAER SUS DATOS PARA LAS VALIDACIONES CRUZADAS
        SELECT id_proveedor, ind_estado, val_total
        INTO   wordencompra_id_proveedor, wordencompra_ind_estado, wordencompra_val_total
        FROM   tab_enc_ordcomp
        WHERE  id_ordencompra = wid_ordencompra;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'La orden de compra % no existe.', wid_ordencompra;
        END IF;

        -- VALIDAR QUE LA ORDEN PERTENEZCA AL MISMO PROVEEDOR DE LA FACTURA
        IF wordencompra_id_proveedor <> wid_proveedor THEN
            RAISE EXCEPTION 'La orden de compra % no pertenece al proveedor % (pertenece a %).', wid_ordencompra, wid_proveedor, wordencompra_id_proveedor;
        END IF;

        -- VALIDAR QUE LA ORDEN ESTÉ APROBADA (1=Aprobado, 2=Pendiente, 3=Anulado)
        IF wordencompra_ind_estado = 2 THEN
            RAISE EXCEPTION 'La orden de compra % está pendiente de aprobación y no puede facturarse.', wid_ordencompra;
        ELSIF wordencompra_ind_estado = 3 THEN
            RAISE EXCEPTION 'La orden de compra % está anulada y no puede facturarse.', wid_ordencompra;
        END IF;

        -- VALIDAR QUE LO YA FACTURADO CONTRA ESTA ORDEN + LA FACTURA NUEVA NO SUPERE EL VALOR TOTAL DE LA ORDEN
        SELECT COALESCE(SUM(val_factura), 0)
        INTO   wtotal_facturado
        FROM   tab_cuentasxpagar
        WHERE  id_ordencompra = wid_ordencompra;

        IF (wtotal_facturado + wval_factura) > wordencompra_val_total THEN
            RAISE EXCEPTION 'El valor de la factura supera el saldo disponible de la orden de compra % (disponible: %, valor total de la orden: %).',
                wid_ordencompra, (wordencompra_val_total - wtotal_facturado), wordencompra_val_total;
        END IF;

    END IF;

-- VALIDAR QUE LA FECHA DE EMISIÓN NO SEA FUTURA
    IF wfec_emision > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de emisión no puede ser mayor a la fecha actual.';
    END IF;

-- VALIDAR QUE LA FECHA DE VENCIMIENTO SEA MAYOR A LA FECHA DE EMISIÓN
    IF wfec_vencimiento < wfec_emision THEN
        RAISE EXCEPTION 'La fecha de vencimiento debe ser mayor a la fecha de emisión.';
    END IF;

-- VALIDAR QUE EL VALOR DE LA FACTURA ESTÉ ENTRE 0 Y 9999999999
    IF wval_factura < 0 OR wval_factura > 9999999999 THEN
        RAISE EXCEPTION 'El valor de la factura debe estar entre 0 y 9.999.999.999.';
    END IF;

-- VALIDAR QUE EL NÚMERO DE CUOTAS ESTÉ ENTRE 1 Y 99
    IF wnum_cuotas < 1 OR wnum_cuotas > 99 THEN
        RAISE EXCEPTION 'El número de cuotas debe estar entre 1 y 99.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_cuentasxpagar
-- (val_saldo lo asigna el trigger aparte, por eso no se incluye acá)
    INSERT INTO tab_cuentasxpagar (id_factura, id_proveedor, id_ordencompra, fec_emision, fec_vencimiento, val_factura, num_cuotas)
    VALUES                        (wid_factura, wid_proveedor, wid_ordencompra, wfec_emision, wfec_vencimiento, wval_factura, wnum_cuotas);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE ENCABEZADO DE CRONOGRAMA DE PAGOS
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_enc_cronopagos (wnom_cronograma     tab_enc_cronopagos.nom_cronograma%TYPE,
                                                      wfec_programacion   tab_enc_cronopagos.fec_programacion%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wid_cronograma      tab_enc_cronopagos.id_cronograma%TYPE;
        wtotal_a_pagar      tab_enc_cronopagos.total_a_pagar%TYPE := 0;

BEGIN

-- VALIDAR QUE LA FECHA DE PROGRAMACIÓN NO SEA NULA
    IF wfec_programacion IS NULL THEN
        RAISE EXCEPTION 'La fecha de programación no puede ser nula.';
    END IF;

-- VALIDAR QUE LA FECHA DE PROGRAMACIÓN SEA MAYOR O IGUAL A LA FECHA ACTUAL
    IF wfec_programacion < CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de programación no puede ser anterior a la fecha actual.';
    END IF;

-- VALIDAR QUE LA FECHA DE PROGRAMACIÓN NO SEA NULA
    IF wnom_cronograma IS NULL THEN
        RAISE EXCEPTION 'El nombre del cronograma no puede ser nulo.';
    END IF;

-- VALIDAR QUE LA FECHA DE PROGRAMACIÓN SEA MAYOR O IGUAL A LA FECHA ACTUAL
    IF wnom_cronograma = '' THEN
        RAISE EXCEPTION 'El nombre del cronograma no puede estar vacío.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_enc_cronopagos

    SELECT COALESCE(MAX(id_cronograma), 0) + 1 INTO wid_cronograma
    FROM tab_enc_cronopagos;

    INSERT INTO tab_enc_cronopagos (id_cronograma, nom_cronograma , fec_programacion, total_a_pagar)
    VALUES (wid_cronograma, wnom_cronograma, wfec_programacion, wtotal_a_pagar);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE DETALLE DE CRONOGRAMA DE PAGOS
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_det_cronopagos (wid_cronograma      tab_det_cronopagos.id_cronograma%TYPE,
                                                      wid_factura         tab_det_cronopagos.id_factura%TYPE,
                                                      wid_cuota           tab_det_cronopagos.id_cuota%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID DEL CRONOGRAMA NO SEA NULO
    IF wid_cronograma IS NULL THEN
        RAISE EXCEPTION 'El ID del cronograma no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL ID DE LA FACTURA NO SEA NULO
    IF wid_factura IS NULL THEN
        RAISE EXCEPTION 'El ID de la factura no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL ID DE LA CUOTA NO SEA NULO
    IF wid_cuota IS NULL THEN
        RAISE EXCEPTION 'El ID de la cuota no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL CRONOGRAMA EXISTA Y ESTÉ PENDIENTE
    IF NOT EXISTS (SELECT 1 FROM tab_enc_cronopagos WHERE id_cronograma = wid_cronograma AND ind_estado = FALSE) THEN
        RAISE EXCEPTION 'El cronograma % no existe o ya fue pagado.', wid_cronograma;
    END IF;

-- VALIDAR QUE LA CUOTA DE LA FACTURA EXISTA EN tab_cuotasxfactura (FK)
    IF NOT EXISTS (SELECT 1 FROM tab_cuotasxfactura WHERE id_factura = wid_factura AND id_cuota = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % no existe.', wid_cuota, wid_factura;
    END IF;

-- VALIDAR QUE LA CUOTA NO ESTÉ YA PAGADA
    IF EXISTS (SELECT 1 FROM tab_cuotasxfactura WHERE id_factura = wid_factura AND id_cuota = wid_cuota AND ind_pagada = TRUE) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya fue pagada.', wid_cuota, wid_factura;
    END IF;

-- VALIDAR QUE NO EXISTA YA ESA COMBINACIÓN EN EL DETALLE DEL CRONOGRAMA (PK COMPUESTA)
    IF EXISTS (SELECT 1 FROM tab_det_cronopagos WHERE id_cronograma = wid_cronograma AND id_factura = wid_factura AND id_cuota = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya está en el cronograma %.', wid_cuota, wid_factura, wid_cronograma;
    END IF;

-- VALIDAR QUE LA CUOTA NO ESTÉ PROGRAMADA EN OTRO CRONOGRAMA
-- Solo se permite si el banco la RECHAZÓ (estado_pago = 3) en cada cronograma
-- anterior donde estuvo: es el reintento de un pago rechazado.
    IF EXISTS (SELECT 1
                 FROM tab_det_cronopagos d
                WHERE d.id_factura    = wid_factura
                  AND d.id_cuota      = wid_cuota
                  AND d.id_cronograma <> wid_cronograma
                  AND NOT EXISTS (SELECT 1
                                    FROM tab_pagos_cxp p
                                   WHERE p.id_cronograma = d.id_cronograma
                                     AND p.id_factura    = d.id_factura
                                     AND p.id_cuota      = d.id_cuota
                                     AND p.estado_pago   = 3)) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya está programada en otro cronograma que el banco no ha rechazado.', wid_cuota, wid_factura;
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_det_cronopagos
    INSERT INTO tab_det_cronopagos (id_cronograma, id_factura, id_cuota)
    VALUES (wid_cronograma, wid_factura, wid_cuota);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE ENCABEZADO DE ARCHIVO PLANO
--    El encabezado ya no lleva id_cronograma: lleva la cuenta de origen de la
--    empresa y la fecha de aplicación. Un archivo puede tener cuotas de varios
--    cronogramas (van en el detalle). El encabezado es el mismo para todos los
--    archivos planos: si es de proveedores, nómina o inversiones se sabe por su
--    tabla de detalle (fun_tipo_archivo_plano).
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_enc_archivo_plano (wnom_archivo        tab_enc_archivo_plano.nom_archivo%TYPE,
                                                         wid_empresa         tab_enc_archivo_plano.id_empresa%TYPE,
                                                         wnom_empresa        tab_enc_archivo_plano.nom_empresa%TYPE,
                                                         wid_banco           tab_enc_archivo_plano.id_banco%TYPE,
                                                         wind_tipocuenta     tab_enc_archivo_plano.ind_tipocuenta%TYPE,
                                                         wcta_empresa        tab_enc_archivo_plano.cta_empresa%TYPE,
                                                         wfecha_aplicacion   tab_enc_archivo_plano.fecha_aplicacion%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wid_archivo_plano   tab_enc_archivo_plano.id_archivo_plano%TYPE;
        wbanco_cuenta       tab_ctas_empresa.id_banco%TYPE;
        wtipocuenta_cuenta  tab_ctas_empresa.ind_tipocuenta%TYPE;
        wdia1               tab_pmtros_tescxp.fec_diapago1%TYPE;
        wdia2               tab_pmtros_tescxp.fec_diapago2%TYPE;
        wdia3               tab_pmtros_tescxp.fec_diapago3%TYPE;
        wnom_festivo        tab_festivos.nom_festivo%TYPE;
        wtabla_err          TEXT;
        wcolumna_err        TEXT;

BEGIN

-- VALIDAR QUE LOS CAMPOS NO SEAN NULOS
    IF wnom_archivo IS NULL THEN
        RAISE EXCEPTION 'El nombre del archivo plano no puede ser nulo.';
    END IF;

    IF wid_empresa IS NULL THEN
        RAISE EXCEPTION 'El ID de la empresa no puede ser nulo.';
    END IF;

    IF wnom_empresa IS NULL THEN
        RAISE EXCEPTION 'El nombre de la empresa no puede ser nulo.';
    END IF;

    IF wid_banco IS NULL THEN
        RAISE EXCEPTION 'El ID del banco no puede ser nulo.';
    END IF;

    IF wind_tipocuenta IS NULL THEN
        RAISE EXCEPTION 'El indicador de tipo de cuenta no puede ser nulo.';
    END IF;

    IF wcta_empresa IS NULL THEN
        RAISE EXCEPTION 'La cuenta de la empresa no puede ser nula.';
    END IF;

    IF wfecha_aplicacion IS NULL THEN
        RAISE EXCEPTION 'La fecha de aplicación no puede ser nula.';
    END IF;

-- VALIDAR LONGITUDES (mismos CHECK de la tabla)
    IF LENGTH(TRIM(wnom_archivo)) < 3 OR LENGTH(wnom_archivo) > 30 THEN
        RAISE EXCEPTION 'El nombre del archivo plano debe tener entre 3 y 30 caracteres.';
    END IF;

    IF LENGTH(TRIM(wnom_empresa)) < 5 OR LENGTH(wnom_empresa) > 60 THEN
        RAISE EXCEPTION 'El nombre de la empresa debe tener entre 5 y 60 caracteres.';
    END IF;

-- VALIDAR QUE LA FECHA DE APLICACIÓN NO SEA PASADA
    IF wfecha_aplicacion < CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de aplicación no puede ser anterior a la fecha actual.';
    END IF;

-- VALIDAR QUE LA FECHA DE APLICACIÓN SEA UN DÍA DE PAGO (tab_pmtros_tescxp)
-- EXTRACT(ISODOW) devuelve 1 = lunes ... 7 = domingo, igual que fec_diapago1..3
    SELECT fec_diapago1, fec_diapago2, fec_diapago3
      INTO wdia1, wdia2, wdia3
      FROM tab_pmtros_tescxp
     WHERE id_empresa  = wid_empresa
       AND ind_borrado = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay días de pago configurados en Parámetros de Tesorería para la empresa %.', wid_empresa;
    END IF;

    IF EXTRACT(ISODOW FROM wfecha_aplicacion) NOT IN (wdia1, wdia2, wdia3) THEN
        RAISE EXCEPTION 'La fecha de aplicación % no es un día de pago configurado en Parámetros de Tesorería.', TO_CHAR(wfecha_aplicacion, 'DD/MM/YYYY');
    END IF;

-- VALIDAR QUE LA FECHA DE APLICACIÓN NO SEA FESTIVO
    SELECT nom_festivo INTO wnom_festivo
      FROM tab_festivos
     WHERE fecha       = wfecha_aplicacion
       AND ind_borrado = FALSE
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'La fecha de aplicación % es festivo (%).', TO_CHAR(wfecha_aplicacion, 'DD/MM/YYYY'), wnom_festivo;
    END IF;

-- VALIDAR QUE LA CUENTA DE LA EMPRESA EXISTA Y ESTÉ ACTIVA (FK)
    SELECT id_banco, ind_tipocuenta
      INTO wbanco_cuenta, wtipocuenta_cuenta
      FROM tab_ctas_empresa
     WHERE id_empresa  = wid_empresa
       AND cta_empresa = wcta_empresa
       AND ind_borrado = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta % no está registrada o está inactiva para la empresa %.', wcta_empresa, wid_empresa;
    END IF;

-- VALIDAR QUE EL BANCO Y EL TIPO DE CUENTA SEAN LOS DE ESA CUENTA
    IF wbanco_cuenta <> wid_banco THEN
        RAISE EXCEPTION 'La cuenta % de la empresa pertenece al banco %, no al banco %.', wcta_empresa, wbanco_cuenta, wid_banco;
    END IF;

    IF wtipocuenta_cuenta <> wind_tipocuenta THEN
        RAISE EXCEPTION 'El tipo de cuenta enviado no coincide con el registrado para la cuenta % de la empresa.', wcta_empresa;
    END IF;

-- VALIDAR QUE EL BANCO ESTÉ ACTIVO
    IF NOT EXISTS (SELECT 1 FROM tab_bancos WHERE id_banco = wid_banco AND ind_borrado = FALSE AND ind_estado = TRUE) THEN
        RAISE EXCEPTION 'El banco % no existe o está inactivo.', wid_banco;
    END IF;

-- SI TODO VA BIEN, SE INSERTA (fec_generacion queda NULL e ind_generado en FALSE)
    SELECT COALESCE(MAX(id_archivo_plano), 0) + 1 INTO wid_archivo_plano
      FROM tab_enc_archivo_plano;

    INSERT INTO tab_enc_archivo_plano (id_archivo_plano, nom_archivo, id_empresa, nom_empresa, id_banco,
                                       ind_tipocuenta, cta_empresa, fecha_aplicacion)
    VALUES                            (wid_archivo_plano, TRIM(wnom_archivo), wid_empresa, TRIM(wnom_empresa), wid_banco,
                                       wind_tipocuenta, wcta_empresa, wfecha_aplicacion);

    RETURN TRUE;

EXCEPTION
    -- Campo obligatorio en NULL: se agrega qué tabla y columna, porque el
    -- mensaje general ("Un campo obligatorio está vacío") no lo dice.
    WHEN not_null_violation THEN
        GET STACKED DIAGNOSTICS wtabla_err = TABLE_NAME, wcolumna_err = COLUMN_NAME;
        RAISE EXCEPTION 'ERROR: % (%.%)', fun_mensaje_error(SQLSTATE, SQLERRM), wtabla_err, wcolumna_err;
    -- Registro duplicado: se agrega la tabla y la restricción que lo impidió.
    WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS wtabla_err = TABLE_NAME, wcolumna_err = CONSTRAINT_NAME;
        RAISE EXCEPTION 'ERROR: % (tabla %, restricción %)', fun_mensaje_error(SQLSTATE, SQLERRM), wtabla_err, wcolumna_err;
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE DETALLE DE ARCHIVO PLANO
-- NOTA: Solo cronogramas pendientes. Una cuota va una sola vez al banco desde
--       cada cronograma; si el banco la rechaza, se reprograma en un
--       cronograma nuevo y desde ahí vuelve a un archivo plano.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_det_archivo_plano (wid_archivo_plano   tab_det_archivo_plano.id_archivo_plano%TYPE,
                                                         wid_cronograma      tab_det_archivo_plano.id_cronograma%TYPE,
                                                         wid_factura         tab_det_archivo_plano.id_factura%TYPE,
                                                         wid_cuota           tab_det_archivo_plano.id_cuota%TYPE,
                                                         wid_tipo            tab_det_archivo_plano.id_tipo%TYPE,
                                                         wid_proveedor       tab_det_archivo_plano.id_proveedor%TYPE,
                                                         wnom_tercero        tab_det_archivo_plano.nom_tercero%TYPE,
                                                         wid_banco           tab_det_archivo_plano.id_banco%TYPE,
                                                         wind_tipocuenta     tab_det_archivo_plano.ind_tipocuenta%TYPE,
                                                         wcta_proveedor      tab_det_archivo_plano.cta_proveedor%TYPE,
                                                         wconcepto           tab_det_archivo_plano.concepto%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wbanco_cuenta       tab_bancoxprov.id_banco%TYPE;
        wtipocuenta_cuenta  tab_bancoxprov.ind_tipocuenta%TYPE;
        wproveedor_factura  tab_cuentasxpagar.id_proveedor%TYPE;
        wval_a_pagar        tab_det_archivo_plano.val_a_pagar%TYPE;
        wcrono_cerrado      tab_enc_cronopagos.ind_estado%TYPE;
        wtabla_err          TEXT;
        wcolumna_err        TEXT;

BEGIN

-- VALIDAR QUE LOS CAMPOS OBLIGATORIOS NO SEAN NULOS (concepto es opcional)
    IF wid_archivo_plano IS NULL THEN
        RAISE EXCEPTION 'El ID del archivo plano no puede ser nulo.';
    END IF;

    IF wid_cronograma IS NULL THEN
        RAISE EXCEPTION 'El ID del cronograma no puede ser nulo.';
    END IF;

    IF wid_factura IS NULL THEN
        RAISE EXCEPTION 'El ID de la factura no puede ser nulo.';
    END IF;

    IF wid_cuota IS NULL THEN
        RAISE EXCEPTION 'El ID de la cuota no puede ser nulo.';
    END IF;

    IF wid_tipo IS NULL THEN
        RAISE EXCEPTION 'El tipo de documento del proveedor no puede ser nulo.';
    END IF;

    IF wid_proveedor IS NULL THEN
        RAISE EXCEPTION 'El ID del proveedor no puede ser nulo.';
    END IF;

    IF wnom_tercero IS NULL THEN
        RAISE EXCEPTION 'El nombre del proveedor no puede ser nulo.';
    END IF;

    IF wid_banco IS NULL THEN
        RAISE EXCEPTION 'El ID del banco no puede ser nulo.';
    END IF;

    IF wind_tipocuenta IS NULL THEN
        RAISE EXCEPTION 'El indicador de tipo de cuenta no puede ser nulo.';
    END IF;

    IF wcta_proveedor IS NULL THEN
        RAISE EXCEPTION 'La cuenta del proveedor no puede ser nula.';
    END IF;

-- VALIDAR FORMATOS Y LONGITUDES (mismos CHECK de la tabla, con mensaje claro)
    IF wid_tipo !~ '^[A-Z]{2,5}$' THEN
        RAISE EXCEPTION 'El tipo de documento debe tener entre 2 y 5 letras mayúsculas (ej. NIT, CC).';
    END IF;

    IF wid_proveedor !~ '^[A-Z0-9]{7,10}$' THEN
        RAISE EXCEPTION 'El ID del proveedor debe tener entre 7 y 10 caracteres alfanuméricos.';
    END IF;

    IF LENGTH(TRIM(wnom_tercero)) < 4 OR LENGTH(wnom_tercero) > 50 THEN
        RAISE EXCEPTION 'El nombre del proveedor debe tener entre 4 y 50 caracteres.';
    END IF;

    IF LENGTH(wid_banco) < 6 OR LENGTH(wid_banco) > 10 THEN
        RAISE EXCEPTION 'El ID del banco debe tener entre 6 y 10 caracteres.';
    END IF;

    IF LENGTH(wcta_proveedor) < 10 OR LENGTH(wcta_proveedor) > 16 THEN
        RAISE EXCEPTION 'La cuenta del proveedor debe tener entre 10 y 16 caracteres.';
    END IF;

    IF wconcepto IS NOT NULL AND LENGTH(wconcepto) > 80 THEN
        RAISE EXCEPTION 'El concepto no puede superar 80 caracteres.';
    END IF;

-- VALIDAR QUE EL ARCHIVO PLANO EXISTA Y NO ESTÉ GENERADO
    IF NOT EXISTS (SELECT 1 FROM tab_enc_archivo_plano
                    WHERE id_archivo_plano = wid_archivo_plano
                      AND ind_generado     = FALSE) THEN
        RAISE EXCEPTION 'El archivo plano % no existe o ya fue generado.', wid_archivo_plano;
    END IF;

-- LOS ARCHIVOS QUE ENVIARON NÓMINA O FINANCIERO NO ADMITEN CUOTAS DE PROVEEDORES
    IF fun_tipo_archivo_plano(wid_archivo_plano) <> 'PROVEEDORES' THEN
        RAISE EXCEPTION 'El archivo plano % es de %: no se le pueden agregar cuotas de proveedores.', wid_archivo_plano,
            CASE fun_tipo_archivo_plano(wid_archivo_plano) WHEN 'NOMINA' THEN 'nómina' ELSE 'inversiones' END;
    END IF;

-- VALIDAR QUE EL CRONOGRAMA EXISTA Y ESTÉ ACTIVO
    SELECT ind_estado INTO wcrono_cerrado
      FROM tab_enc_cronopagos
     WHERE id_cronograma = wid_cronograma
       AND ind_borrado   = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cronograma % no existe o está inactivo.', wid_cronograma;
    END IF;

-- UN CRONOGRAMA CERRADO (el banco ya respondió todas sus cuotas) NO ADMITE
-- NADA MÁS. Las cuotas rechazadas se reprograman en un cronograma nuevo.
    IF wcrono_cerrado = TRUE THEN
        RAISE EXCEPTION 'El cronograma % ya fue pagado. Si el banco rechazó cuotas, inclúyalas en un cronograma nuevo.', wid_cronograma;
    END IF;

-- UNA CUOTA SOLO VA UNA VEZ AL BANCO DESDE EL MISMO CRONOGRAMA
    IF EXISTS (SELECT 1 FROM tab_det_archivo_plano
                WHERE id_cronograma = wid_cronograma
                  AND id_factura    = wid_factura
                  AND id_cuota      = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya se envió al banco desde el cronograma %. Si fue rechazada, inclúyala en un cronograma nuevo.', wid_cuota, wid_factura, wid_cronograma;
    END IF;

-- VALIDAR QUE LA CUOTA ESTÉ PROGRAMADA EN ESE CRONOGRAMA (FK a tab_det_cronopagos)
    IF NOT EXISTS (SELECT 1 FROM tab_det_cronopagos
                    WHERE id_cronograma = wid_cronograma
                      AND id_factura    = wid_factura
                      AND id_cuota      = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % no está programada en el cronograma %.', wid_cuota, wid_factura, wid_cronograma;
    END IF;

-- VALOR A PAGAR: se copia el valor de la cuota de la factura
-- (tab_cuotasxfactura.val_cuota). Queda guardado en la línea como historial
-- de lo que se envió al banco, aunque después cambie la factura.
    SELECT val_cuota INTO wval_a_pagar
      FROM tab_cuotasxfactura
     WHERE id_factura = wid_factura
       AND id_cuota   = wid_cuota;

    IF wval_a_pagar IS NULL OR wval_a_pagar <= 0 THEN
        RAISE EXCEPTION 'La cuota % de la factura % no tiene valor a pagar.', wid_cuota, wid_factura;
    END IF;

-- VALIDAR QUE LA CUOTA NO ESTÉ YA PAGADA
    IF EXISTS (SELECT 1 FROM tab_cuotasxfactura
                WHERE id_factura = wid_factura
                  AND id_cuota   = wid_cuota
                  AND ind_pagada = TRUE) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya fue pagada.', wid_cuota, wid_factura;
    END IF;

-- VALIDAR QUE EL PROVEEDOR SEA EL DUEÑO DE LA FACTURA
    SELECT id_proveedor INTO wproveedor_factura
      FROM tab_cuentasxpagar
     WHERE id_factura = wid_factura;

    IF wproveedor_factura IS DISTINCT FROM wid_proveedor THEN
        RAISE EXCEPTION 'La factura % pertenece al proveedor %, no al proveedor %.', wid_factura, wproveedor_factura, wid_proveedor;
    END IF;

-- VALIDAR QUE LA CUOTA NO ESTÉ YA EN ESTE MISMO ARCHIVO (PK)
    IF EXISTS (SELECT 1 FROM tab_det_archivo_plano
                WHERE id_archivo_plano = wid_archivo_plano
                  AND id_factura       = wid_factura
                  AND id_cuota         = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya está en el archivo plano %.', wid_cuota, wid_factura, wid_archivo_plano;
    END IF;

-- VALIDAR QUE LA CUOTA NO ESTÉ EN OTRO ARCHIVO PLANO VIGENTE
-- Solo se permite si todas las líneas anteriores de la cuota tienen un pago
-- RECHAZADO (estado_pago = 3) (reintento). Bloquea si está en un archivo sin respuesta del
-- banco, o con un pago PENDIENTE o APROBADO.
    IF EXISTS (SELECT 1
                 FROM tab_det_archivo_plano d
                WHERE d.id_factura = wid_factura
                  AND d.id_cuota   = wid_cuota
                  AND NOT EXISTS (SELECT 1
                                    FROM tab_pagos_cxp p
                                   WHERE p.id_archivo_plano = d.id_archivo_plano
                                     AND p.id_cronograma    = d.id_cronograma
                                     AND p.id_factura       = d.id_factura
                                     AND p.id_cuota         = d.id_cuota
                                     AND p.estado_pago      = 3)) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya está en otro archivo plano que no ha sido rechazado.', wid_cuota, wid_factura;
    END IF;

-- VALIDAR QUE LA CUENTA DEL PROVEEDOR EXISTA Y ESTÉ ACTIVA (FK a tab_bancoxprov)
    SELECT id_banco, ind_tipocuenta
      INTO wbanco_cuenta, wtipocuenta_cuenta
      FROM tab_bancoxprov
     WHERE id_proveedor  = wid_proveedor
       AND cta_proveedor = wcta_proveedor
       AND ind_borrado   = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta % no está registrada o está inactiva para el proveedor %.', wcta_proveedor, wid_proveedor;
    END IF;

-- VALIDAR QUE EL BANCO Y EL TIPO DE CUENTA COINCIDAN CON LOS DE LA CUENTA
-- (son una copia; si no coinciden, el banco recibiría datos inconsistentes)
    IF wbanco_cuenta <> wid_banco THEN
        RAISE EXCEPTION 'La cuenta % del proveedor % pertenece al banco %, no al banco %.', wcta_proveedor, wid_proveedor, wbanco_cuenta, wid_banco;
    END IF;

    IF wtipocuenta_cuenta <> wind_tipocuenta THEN
        RAISE EXCEPTION 'El tipo de cuenta enviado no coincide con el registrado para la cuenta % del proveedor %.', wcta_proveedor, wid_proveedor;
    END IF;

-- VALIDAR QUE EL BANCO EXISTA Y ESTÉ ACTIVO
    IF NOT EXISTS (SELECT 1 FROM tab_bancos
                    WHERE id_banco    = wid_banco
                      AND ind_borrado = FALSE
                      AND ind_estado  = TRUE) THEN
        RAISE EXCEPTION 'El banco % no existe o está inactivo.', wid_banco;
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_det_archivo_plano
    INSERT INTO tab_det_archivo_plano (id_archivo_plano, id_cronograma, id_factura, id_cuota,
                                       id_tipo, id_proveedor, nom_tercero, id_banco,
                                       ind_tipocuenta, cta_proveedor, val_a_pagar, concepto)
    VALUES                            (wid_archivo_plano, wid_cronograma, wid_factura, wid_cuota,
                                       wid_tipo, wid_proveedor, TRIM(wnom_tercero), wid_banco,
                                       wind_tipocuenta, wcta_proveedor, wval_a_pagar, NULLIF(TRIM(wconcepto), ''));

    RETURN TRUE;

EXCEPTION
    -- Campo obligatorio en NULL: se agrega qué tabla y columna, porque el
    -- mensaje general ("Un campo obligatorio está vacío") no lo dice.
    WHEN not_null_violation THEN
        GET STACKED DIAGNOSTICS wtabla_err = TABLE_NAME, wcolumna_err = COLUMN_NAME;
        RAISE EXCEPTION 'ERROR: % (%.%)', fun_mensaje_error(SQLSTATE, SQLERRM), wtabla_err, wcolumna_err;
    -- Registro duplicado: se agrega la tabla y la restricción que lo impidió.
    WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS wtabla_err = TABLE_NAME, wcolumna_err = CONSTRAINT_NAME;
        RAISE EXCEPTION 'ERROR: % (tabla %, restricción %)', fun_mensaje_error(SQLSTATE, SQLERRM), wtabla_err, wcolumna_err;
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE CÓDIGOS DE RESPUESTA DEL BANCO
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_codigos_respuesta_banco (wid_codigo      tab_codigos_respuesta_banco.id_codigo%TYPE,
                                                               wid_banco       tab_codigos_respuesta_banco.id_banco%TYPE,
                                                               wdes_motivo     tab_codigos_respuesta_banco.des_motivo%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE LOS CAMPOS NO SEAN NULOS
    IF wid_codigo IS NULL THEN
        RAISE EXCEPTION 'El código de respuesta no puede ser nulo.';
    END IF;

    IF wid_banco IS NULL THEN
        RAISE EXCEPTION 'El ID del banco no puede ser nulo.';
    END IF;

    IF wdes_motivo IS NULL THEN
        RAISE EXCEPTION 'La descripción del código no puede ser nula.';
    END IF;

-- VALIDAR LONGITUDES (mismos CHECK de la tabla)
    IF LENGTH(TRIM(wid_codigo)) < 1 OR LENGTH(wid_codigo) > 10 THEN
        RAISE EXCEPTION 'El código de respuesta debe tener entre 1 y 10 caracteres.';
    END IF;

    IF LENGTH(TRIM(wdes_motivo)) < 3 OR LENGTH(wdes_motivo) > 100 THEN
        RAISE EXCEPTION 'La descripción del código debe tener entre 3 y 100 caracteres.';
    END IF;

-- VALIDAR QUE EL BANCO EXISTA Y NO ESTÉ BORRADO
    IF NOT EXISTS (SELECT 1 FROM tab_bancos WHERE id_banco = wid_banco AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El banco % no existe o se encuentra borrado.', wid_banco;
    END IF;

-- VALIDAR QUE EL CÓDIGO NO EXISTA YA PARA ESE BANCO (PK)
    IF EXISTS (SELECT 1 FROM tab_codigos_respuesta_banco WHERE id_codigo = wid_codigo AND id_banco = wid_banco) THEN
        RAISE EXCEPTION 'El código % ya está registrado para el banco %.', wid_codigo, wid_banco;
    END IF;

-- SI TODO VA BIEN, SE INSERTA (ind_borrado QUEDA EN FALSE POR EL DEFAULT)
    INSERT INTO tab_codigos_respuesta_banco (id_codigo, id_banco, des_motivo)
    VALUES                                  (TRIM(wid_codigo), wid_banco, TRIM(wdes_motivo));

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE BANCOS
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_bancos (wid_banco     tab_bancos.id_banco%TYPE,
                                              wnom_banco     tab_bancos.nom_banco%TYPE,
                                              wind_estado    tab_bancos.ind_estado%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID DEL BANCO NO SEA NULO
    IF wid_banco IS NULL THEN
        RAISE EXCEPTION 'El ID del banco no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL NOMBRE DEL BANCO NO SEA NULO
    IF wnom_banco IS NULL THEN
        RAISE EXCEPTION 'El nombre del banco no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL INDICADOR DE ESTADO NO SEA NULO
    IF wind_estado IS NULL THEN
        RAISE EXCEPTION 'El indicador de estado no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL NOMBRE DEL BANCO NO SEA VACÍO
    IF wnom_banco = '' THEN
        RAISE EXCEPTION 'El nombre del banco no puede estar vacío.';
    END IF;

-- VALIDAR QUE EL BANCO NO EXISTA YA (PK)
    IF EXISTS (SELECT 1 FROM tab_bancos WHERE id_banco = wid_banco) THEN
        RAISE EXCEPTION 'El banco % ya existe.', wid_banco;
    END IF;

-- VALIDAR QUE EL ID DEL BANCO TENGA ENTRE 6 Y 10 CARACTERES
    IF LENGTH(wid_banco) < 6 OR LENGTH(wid_banco) > 10 THEN
        RAISE EXCEPTION 'El ID del banco debe tener entre 6 y 10 caracteres.';
    END IF;

-- VALIDAR QUE EL NOMBRE DEL BANCO TENGA ENTRE 4 Y 50 CARACTERES
    IF LENGTH(wnom_banco) < 4 OR LENGTH(wnom_banco) > 50 THEN
        RAISE EXCEPTION 'El nombre del banco debe tener entre 4 y 50 caracteres.';
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_bancos (ind_borrado QUEDA EN FALSE POR EL DEFAULT DE LA TABLA)
    INSERT INTO tab_bancos (id_banco, nom_banco, ind_estado)
    VALUES                 (wid_banco, wnom_banco, wind_estado);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN AUXILIAR: CERRAR EL CRONOGRAMA CUANDO EL BANCO YA LO PROCESÓ
-- El cronograma pasa a "pagado" (ind_estado = TRUE) cuando TODAS sus cuotas
-- tienen respuesta definitiva del banco: pagada (pago APROBADO) o con un pago
-- RECHAZADO. No importa que algunas hayan sido rechazadas: el cronograma ya se
-- pagó y queda cerrado (no se edita ni se borra). Las cuotas rechazadas siguen
-- sin pagar y se pueden reintentar en un archivo plano nuevo.
-- Una cuota sin enviar, en un archivo sin respuesta o con pago PENDIENTE (1)
-- deja el cronograma abierto.
-- La usan fun_insert_pagos_cxp y fun_update_pagos_cxp. No se llama desde PHP.
-- Devuelve TRUE si cerró el cronograma en esta llamada.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_cerrar_cronograma_procesado (wid_cronograma  tab_enc_cronopagos.id_cronograma%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

    UPDATE tab_enc_cronopagos e
    SET    ind_estado = TRUE
    WHERE  e.id_cronograma = wid_cronograma
      AND  e.ind_estado    = FALSE
      AND  EXISTS (SELECT 1 FROM tab_det_cronopagos d WHERE d.id_cronograma = e.id_cronograma)
      AND  NOT EXISTS (SELECT 1
                         FROM tab_det_cronopagos d
                         JOIN tab_cuotasxfactura c ON c.id_factura = d.id_factura
                                                  AND c.id_cuota   = d.id_cuota
                        WHERE d.id_cronograma = e.id_cronograma
                          AND c.ind_pagada    = FALSE
                          AND NOT EXISTS (SELECT 1
                                            FROM tab_pagos_cxp p
                                           WHERE p.id_cronograma = d.id_cronograma
                                             AND p.id_factura    = d.id_factura
                                             AND p.id_cuota      = d.id_cuota
                                             AND p.estado_pago   = 3));

    RETURN FOUND;
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN AUXILIAR: EFECTOS DE UN PAGO APROBADO
-- La usan fun_insert_pagos_cxp y fun_update_pagos_cxp cuando el pago queda
-- en 2 (APROBADO). No se llama desde PHP.
--   1) Marca la cuota como pagada (trg_actualizar_saldo_factura descuenta el
--      saldo de la factura y trg_actualizar_saldo_proveedor la deuda).
--   2) Cierra el cronograma si ya todas sus cuotas tienen respuesta definitiva.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_aplicar_pago_aprobado (wid_factura      tab_pagos_cxp.id_factura%TYPE,
                                                      wid_cuota        tab_pagos_cxp.id_cuota%TYPE,
                                                      wid_cronograma   tab_pagos_cxp.id_cronograma%TYPE) RETURNS VOID AS
$BODY$
BEGIN

    UPDATE tab_cuotasxfactura
    SET    ind_pagada = TRUE
    WHERE  id_factura = wid_factura
      AND  id_cuota   = wid_cuota
      AND  ind_pagada = FALSE;

    PERFORM fun_cerrar_cronograma_procesado(wid_cronograma);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE PAGOS DE CUENTAS POR PAGAR
-- NOTA: Registra la respuesta del banco para UNA línea de un archivo plano.
--       Toma de la línea id_cronograma y val_a_pagar, y del encabezado el
--       banco; por eso PHP solo manda archivo, factura, cuota, fecha, estado
--       y código.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_pagos_cxp (wid_archivo_plano  tab_pagos_cxp.id_archivo_plano%TYPE,
                                                 wid_factura        tab_pagos_cxp.id_factura%TYPE,
                                                 wid_cuota          tab_pagos_cxp.id_cuota%TYPE,
                                                 wfec_pago          tab_pagos_cxp.fec_pago%TYPE,
                                                 westado_pago       tab_pagos_cxp.estado_pago%TYPE,
                                                 wid_codigo         tab_pagos_cxp.id_codigo%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wid_pago        tab_pagos_cxp.id_pago%TYPE;
        wid_cronograma  tab_det_archivo_plano.id_cronograma%TYPE;
        wval_pago       tab_det_archivo_plano.val_a_pagar%TYPE;
        wid_banco       tab_enc_archivo_plano.id_banco%TYPE;
        wind_generado   tab_enc_archivo_plano.ind_generado%TYPE;
        wfec_generacion tab_enc_archivo_plano.fec_generacion%TYPE;

BEGIN

-- VALIDAR QUE LOS CAMPOS NO SEAN NULOS
    IF wid_archivo_plano IS NULL THEN
        RAISE EXCEPTION 'El ID del archivo plano no puede ser nulo.';
    END IF;

    IF wid_factura IS NULL THEN
        RAISE EXCEPTION 'El ID de la factura no puede ser nulo.';
    END IF;

    IF wid_cuota IS NULL THEN
        RAISE EXCEPTION 'El ID de la cuota no puede ser nulo.';
    END IF;

    IF wfec_pago IS NULL THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser nula.';
    END IF;

    IF westado_pago IS NULL THEN
        RAISE EXCEPTION 'El estado del pago no puede ser nulo.';
    END IF;

    IF wid_codigo IS NULL THEN
        RAISE EXCEPTION 'El código de respuesta del banco no puede ser nulo.';
    END IF;

-- VALIDAR EL ESTADO (1 = PENDIENTE, 2 = APROBADO, 3 = RECHAZADO)
    IF westado_pago NOT IN (1, 2, 3) THEN
        RAISE EXCEPTION 'El estado % no es válido: debe ser 1 (Pendiente), 2 (Aprobado) o 3 (Rechazado).', westado_pago;
    END IF;

-- VALIDAR QUE EL ARCHIVO PLANO EXISTA Y YA ESTÉ GENERADO (ENVIADO AL BANCO)
    SELECT id_banco, ind_generado, fec_generacion
      INTO wid_banco, wind_generado, wfec_generacion
      FROM tab_enc_archivo_plano
     WHERE id_archivo_plano = wid_archivo_plano;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El archivo plano % no existe.', wid_archivo_plano;
    END IF;

    IF wind_generado = FALSE THEN
        RAISE EXCEPTION 'El archivo plano % todavía no ha sido generado; no puede tener respuesta del banco.', wid_archivo_plano;
    END IF;

-- VALIDAR QUE LA CUOTA ESTÉ EN ESE ARCHIVO Y TRAER CRONOGRAMA Y VALOR
    SELECT id_cronograma, val_a_pagar
      INTO wid_cronograma, wval_pago
      FROM tab_det_archivo_plano
     WHERE id_archivo_plano = wid_archivo_plano
       AND id_factura       = wid_factura
       AND id_cuota         = wid_cuota;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuota % de la factura % no está en el archivo plano %.', wid_cuota, wid_factura, wid_archivo_plano;
    END IF;

-- VALIDAR QUE ESA LÍNEA NO TENGA YA UNA RESPUESTA REGISTRADA
    IF EXISTS (SELECT 1 FROM tab_pagos_cxp
                WHERE id_archivo_plano = wid_archivo_plano
                  AND id_factura       = wid_factura
                  AND id_cuota         = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya tiene una respuesta registrada en el archivo plano %. Si está pendiente, actualícela.', wid_cuota, wid_factura, wid_archivo_plano;
    END IF;

-- VALIDAR QUE LA CUOTA NO ESTÉ YA PAGADA
    IF EXISTS (SELECT 1 FROM tab_cuotasxfactura
                WHERE id_factura = wid_factura
                  AND id_cuota   = wid_cuota
                  AND ind_pagada = TRUE) THEN
        RAISE EXCEPTION 'La cuota % de la factura % ya fue pagada.', wid_cuota, wid_factura;
    END IF;

-- VALIDAR QUE EL CÓDIGO EXISTA Y ESTÉ ACTIVO PARA EL BANCO DEL ARCHIVO
    IF NOT EXISTS (SELECT 1 FROM tab_codigos_respuesta_banco
                    WHERE id_codigo   = wid_codigo
                      AND id_banco    = wid_banco
                      AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El código % no existe o está inactivo para el banco % del archivo plano.', wid_codigo, wid_banco;
    END IF;

-- VALIDAR LA FECHA DE PAGO: NO FUTURA NI ANTERIOR A LA GENERACIÓN DEL ARCHIVO
    IF wfec_pago > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser futura.';
    END IF;

    IF wfec_generacion IS NOT NULL AND wfec_pago < wfec_generacion THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser anterior a la generación del archivo plano (%).', TO_CHAR(wfec_generacion, 'DD/MM/YYYY');
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_pagos_cxp
    SELECT COALESCE(MAX(id_pago), 0) + 1 INTO wid_pago
      FROM tab_pagos_cxp;

    INSERT INTO tab_pagos_cxp (id_pago, id_factura, id_cuota, id_archivo_plano, id_cronograma,
                               fec_pago, val_pago, estado_pago, id_codigo, id_banco)
    VALUES                    (wid_pago, wid_factura, wid_cuota, wid_archivo_plano, wid_cronograma,
                               wfec_pago, wval_pago, westado_pago, wid_codigo, wid_banco);

-- APROBADO: cuota pagada y, si ya no queda nada por responder, cronograma cerrado.
-- RECHAZADO: la cuota sigue sin pagar, pero también puede cerrar el cronograma.
    IF westado_pago = 2 THEN
        PERFORM fun_aplicar_pago_aprobado(wid_factura, wid_cuota, wid_cronograma);
    ELSIF westado_pago = 3 THEN
        PERFORM fun_cerrar_cronograma_procesado(wid_cronograma);
    END IF;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN AUXILIAR: ¿DE QUÉ ES UN ARCHIVO PLANO?
-- El encabezado (tab_enc_archivo_plano) es el mismo para todos los archivos:
-- no guarda el tipo. Se sabe por la tabla de detalle que tiene sus líneas:
--     tab_det_archivo_nomina     → 'NOMINA'       (lo envió Gestión Humana)
--     tab_det_archivo_inversion  → 'INVERSION'    (lo envió el área Financiera)
--     tab_det_archivo_plano      → 'PROVEEDORES'  (lo armó Tesorería; también
--                                                   un encabezado aún sin líneas)
-- NULL si el archivo no existe.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_tipo_archivo_plano (wid_archivo_plano  tab_enc_archivo_plano.id_archivo_plano%TYPE) RETURNS VARCHAR AS
$BODY$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tab_enc_archivo_plano WHERE id_archivo_plano = wid_archivo_plano) THEN
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM tab_det_archivo_nomina WHERE id_archivo_plano = wid_archivo_plano) THEN
        RETURN 'NOMINA';
    END IF;

    IF EXISTS (SELECT 1 FROM tab_det_archivo_inversion WHERE id_archivo_plano = wid_archivo_plano) THEN
        RETURN 'INVERSION';
    END IF;

    RETURN 'PROVEEDORES';
END;
$BODY$
LANGUAGE PLPGSQL STABLE;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN AUXILIAR: PRÓXIMA FECHA DE APLICACIÓN VÁLIDA DESDE UNA FECHA
-- Misma regla que fun_insert_enc_archivo_plano: no pasada, día de pago de
-- Parámetros de Tesorería y no festivo. NULL si no hay días de pago
-- configurados o no se encuentra una en 120 días.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_proxima_fecha_pago (wid_empresa  tab_pmtros_tescxp.id_empresa%TYPE,
                                                   wdesde       DATE) RETURNS DATE AS
$BODY$
DECLARE wdia1   tab_pmtros_tescxp.fec_diapago1%TYPE;
        wdia2   tab_pmtros_tescxp.fec_diapago2%TYPE;
        wdia3   tab_pmtros_tescxp.fec_diapago3%TYPE;
        wfecha  DATE;
BEGIN
    SELECT fec_diapago1, fec_diapago2, fec_diapago3
      INTO wdia1, wdia2, wdia3
      FROM tab_pmtros_tescxp
     WHERE id_empresa  = wid_empresa
       AND ind_borrado = FALSE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    wfecha := GREATEST(COALESCE(wdesde, CURRENT_DATE), CURRENT_DATE);
    FOR i IN 0..120 LOOP
        IF EXTRACT(ISODOW FROM wfecha) IN (wdia1, wdia2, wdia3)
           AND NOT EXISTS (SELECT 1 FROM tab_festivos WHERE fecha = wfecha AND ind_borrado = FALSE) THEN
            RETURN wfecha;
        END IF;
        wfecha := wfecha + 1;
    END LOOP;

    RETURN NULL;
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN: ENVIAR NÓMINA A TESORERÍA
-- La llama el botón "Enviar nómina a Tesorería" del módulo de Nómina.
--
--   SELECT fun_enviar_nomina_tesoreria(2026, 11, 1);   -- devuelve el id del archivo plano
--
-- - Toma los empleados del periodo con estado_pago 0 (sin enviar) o 3
--   (rechazados por el banco: se reenvían con la cuenta corregida), que no
--   estén marcados como pagados (ind_pagado) y con neto mayor a cero.
-- - Desde el envío, la nómina ya no se puede volver a liquidar
--   (trg_bloquear_nomina_enviada) hasta que Tesorería la devuelva.
-- - Valida banco y cuenta de cada empleado; si alguno falla no se envía nada
--   y el mensaje dice quiénes.
-- - Encabezado normal (el mismo de todos los archivos planos): la primera
--   cuenta activa de la empresa y la próxima fecha de pago válida. Tesorería
--   puede cambiar cuenta, fecha y nombre antes de descargarlo. El periodo no
--   va en el encabezado: está en cada línea de tab_det_archivo_nomina.
-- - Deja los empleados enviados en estado_pago = 1.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_enviar_nomina_tesoreria (wano_nomina   tab_nomina.ano_nomina%TYPE,
                                                        wmes_nomina   tab_nomina.mes_nomina%TYPE,
                                                        wval_periodo  tab_nomina.val_periodo%TYPE) RETURNS DECIMAL AS
$BODY$

DECLARE wid_archivo_plano   tab_enc_archivo_plano.id_archivo_plano%TYPE;
        wid_empresa         tab_pmtros_grales.id_empresa%TYPE;
        wnom_empresa        tab_pmtros_grales.nom_empresa%TYPE;
        wcta                RECORD;
        wfecha_aplicacion   DATE;
        wnom_archivo        tab_enc_archivo_plano.nom_archivo%TYPE;
        wconcepto           VARCHAR(80);
        wenvios_previos     INTEGER;
        wcantidad           INTEGER;
        werrores            TEXT;
        wcant_errores       INTEGER;

BEGIN

-- VALIDAR PARÁMETROS
    IF wano_nomina IS NULL OR wmes_nomina IS NULL OR wval_periodo IS NULL THEN
        RAISE EXCEPTION 'Indique año, mes y periodo de la nómina a enviar.';
    END IF;

    IF wmes_nomina NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'El mes % no es válido.', wmes_nomina;
    END IF;

    IF wval_periodo NOT IN (1, 2) THEN
        RAISE EXCEPTION 'El periodo % no es válido: debe ser 1 o 2.', wval_periodo;
    END IF;

-- VALIDAR QUE LA NÓMINA DEL PERIODO EXISTA
    IF NOT EXISTS (SELECT 1 FROM tab_nomina
                    WHERE ano_nomina  = wano_nomina
                      AND mes_nomina  = wmes_nomina
                      AND val_periodo = wval_periodo
                      AND ind_borrado IS NOT TRUE) THEN
        RAISE EXCEPTION 'No hay nómina liquidada para %-%, periodo %.', wano_nomina, LPAD(wmes_nomina::TEXT, 2, '0'), wval_periodo;
    END IF;

-- BLOQUEAR LOS REGISTROS DEL PERIODO: si alguien da doble clic, la segunda
-- llamada espera aquí y después ya no encuentra empleados pendientes.
    PERFORM 1
       FROM tab_nomina
      WHERE ano_nomina  = wano_nomina
        AND mes_nomina  = wmes_nomina
        AND val_periodo = wval_periodo
        AND ind_borrado = FALSE
      FOR UPDATE;

-- ¿HAY EMPLEADOS PARA ENVIAR? (sin enviar o rechazados, con neto mayor a cero)
    SELECT COUNT(id_empleado) INTO wcantidad
      FROM tab_nomina
     WHERE ano_nomina  = wano_nomina
       AND mes_nomina  = wmes_nomina
       AND val_periodo = wval_periodo
       AND ind_borrado = FALSE
       AND estado_pago IN (0, 3)
       AND ind_pagado  IS NOT TRUE
       AND val_neto    > 0;

    IF wcantidad = 0 THEN
        RAISE EXCEPTION 'No hay empleados pendientes de enviar en %-%, periodo %: ya fueron enviados a Tesorería o pagados.',
            wano_nomina, LPAD(wmes_nomina::TEXT, 2, '0'), wval_periodo;
    END IF;

-- VALIDAR DATOS BANCARIOS DE CADA EMPLEADO (se listan todos los que fallan)
    SELECT COUNT(x.motivo),
           STRING_AGG(x.motivo, '; ' ORDER BY x.motivo)
      INTO wcant_errores, werrores
      FROM (SELECT TRIM(e.nom_empleado || ' ' || e.ape_empleado) || ' (' || n.id_empleado || '): ' ||
                   CASE
                       WHEN e.id_empleado IS NULL                                 THEN 'no existe en Empleados'
                       WHEN COALESCE(TRIM(e.id_banco), '') = ''                   THEN 'sin banco'
                       WHEN b.id_banco IS NULL                                    THEN 'el banco ' || e.id_banco || ' no existe'
                       WHEN b.ind_borrado OR NOT b.ind_estado                     THEN 'el banco ' || b.nom_banco || ' está inactivo'
                       WHEN COALESCE(e.num_cuenta, '') !~ '^[0-9]{6,20}$'         THEN 'número de cuenta no válido (solo dígitos, 6 a 20)'
                       WHEN COALESCE(e.id_tipo, '') !~ '^[A-Z]{2,5}$'             THEN 'tipo de documento no válido'
                   END AS motivo
              FROM tab_nomina          n
              LEFT JOIN tab_empleados  e ON e.id_empleado = n.id_empleado
              LEFT JOIN tab_bancos     b ON b.id_banco    = e.id_banco
             WHERE n.ano_nomina  = wano_nomina
               AND n.mes_nomina  = wmes_nomina
               AND n.val_periodo = wval_periodo
               AND n.ind_borrado = FALSE
               AND n.estado_pago IN (0, 3)
               AND n.ind_pagado  IS NOT TRUE
               AND n.val_neto    > 0) x
     WHERE x.motivo IS NOT NULL;

    IF wcant_errores > 0 THEN
        RAISE EXCEPTION 'No se envió la nómina: % empleado(s) con datos bancarios incompletos. %', wcant_errores, werrores;
    END IF;

-- EMPRESA (Parámetros Generales)
    SELECT id_empresa, nom_empresa
      INTO wid_empresa, wnom_empresa
      FROM tab_pmtros_grales
     WHERE ind_borrado = FALSE
     ORDER BY id_empresa
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay empresa configurada en Parámetros Generales.';
    END IF;

-- CUENTA DE ORIGEN: la primera cuenta activa de la empresa con banco activo
-- (mismo orden que el select de Archivo Plano). Tesorería la puede cambiar.
    SELECT c.cta_empresa, c.id_banco, c.ind_tipocuenta
      INTO wcta
      FROM tab_ctas_empresa c
      JOIN tab_bancos       b ON b.id_banco = c.id_banco
     WHERE c.id_empresa  = wid_empresa
       AND c.ind_borrado = FALSE
       AND b.ind_borrado = FALSE
       AND b.ind_estado  = TRUE
     ORDER BY b.nom_banco, c.cta_empresa
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tesorería no tiene cuentas bancarias activas para pagar la nómina. Avise a Tesorería.';
    END IF;

-- FECHA DE APLICACIÓN: próximo día de pago que no sea festivo
    IF NOT EXISTS (SELECT 1 FROM tab_pmtros_tescxp WHERE id_empresa = wid_empresa AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'Tesorería no tiene configurados los días de pago (Parámetros de Tesorería). Avise a Tesorería.';
    END IF;

    wfecha_aplicacion := fun_proxima_fecha_pago(wid_empresa, CURRENT_DATE);
    IF wfecha_aplicacion IS NULL THEN
        RAISE EXCEPTION 'No se encontró una fecha de pago válida en los próximos 120 días. Revise Parámetros de Tesorería y Festivos.';
    END IF;

-- NOMBRE: NOMINA_2026_11_P1, y _R2, _R3... si el periodo ya se había enviado antes
-- (archivos con líneas de ese periodo en tab_det_archivo_nomina)
    SELECT COUNT(DISTINCT id_archivo_plano) INTO wenvios_previos
      FROM tab_det_archivo_nomina
     WHERE ano_nomina  = wano_nomina
       AND mes_nomina  = wmes_nomina
       AND val_periodo = wval_periodo;

    wnom_archivo := 'NOMINA_' || wano_nomina || '_' || LPAD(wmes_nomina::TEXT, 2, '0') || '_P' || wval_periodo
                 || CASE WHEN wenvios_previos > 0 THEN '_R' || (wenvios_previos + 1) ELSE '' END;

    wconcepto := 'Nomina ' || wano_nomina || '-' || LPAD(wmes_nomina::TEXT, 2, '0') || ' periodo ' || wval_periodo;

-- ENCABEZADO (el mismo de todos los archivos planos)
    LOCK TABLE tab_enc_archivo_plano IN SHARE ROW EXCLUSIVE MODE;   -- el MAX + 1 no se cruza con otro envío

    SELECT COALESCE(MAX(id_archivo_plano), 0) + 1 INTO wid_archivo_plano
      FROM tab_enc_archivo_plano;

    INSERT INTO tab_enc_archivo_plano (id_archivo_plano, nom_archivo, id_empresa, nom_empresa, id_banco,
                                       ind_tipocuenta, cta_empresa, fecha_aplicacion)
    VALUES                            (wid_archivo_plano, wnom_archivo, wid_empresa, TRIM(wnom_empresa), wcta.id_banco,
                                       wcta.ind_tipocuenta, wcta.cta_empresa, wfecha_aplicacion);

-- DETALLE: copia de los datos bancarios del empleado y el neto a pagar
    INSERT INTO tab_det_archivo_nomina (id_archivo_plano, ano_nomina, mes_nomina, val_periodo, id_empleado,
                                        id_tipo, nom_empleado, id_banco, ind_tipocuenta, num_cuenta,
                                        val_a_pagar, concepto)
    SELECT wid_archivo_plano, n.ano_nomina, n.mes_nomina, n.val_periodo, n.id_empleado,
           e.id_tipo,
           LEFT(TRIM(e.nom_empleado || ' ' || e.ape_empleado), 100),
           e.id_banco,
           COALESCE(e.ind_tipocuenta, FALSE),
           e.num_cuenta,
           n.val_neto,
           wconcepto
      FROM tab_nomina    n
      JOIN tab_empleados e ON e.id_empleado = n.id_empleado
     WHERE n.ano_nomina  = wano_nomina
       AND n.mes_nomina  = wmes_nomina
       AND n.val_periodo = wval_periodo
       AND n.ind_borrado = FALSE
       AND n.estado_pago IN (0, 3)
       AND n.ind_pagado  IS NOT TRUE
       AND n.val_neto    > 0;

-- MARCAR LOS EMPLEADOS COMO ENVIADOS
    UPDATE tab_nomina n
       SET estado_pago      = 1,
           fec_pago         = NULL,
           id_archivo_plano = wid_archivo_plano
      FROM tab_det_archivo_nomina d
     WHERE d.id_archivo_plano = wid_archivo_plano
       AND n.ano_nomina       = d.ano_nomina
       AND n.mes_nomina       = d.mes_nomina
       AND n.val_periodo      = d.val_periodo
       AND n.id_empleado      = d.id_empleado;

    RETURN wid_archivo_plano;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN AUXILIAR: REFLEJAR LA RESPUESTA DEL BANCO EN tab_nomina
-- 2 = APROBADO → empleado PAGADO (con la fecha del banco)
-- 3 = RECHAZADO → empleado RECHAZADO (Nómina corrige la cuenta y lo reenvía)
-- 1 = PENDIENTE → sigue enviado
-- Si con este pago ya no queda ningún empleado del periodo por pagar (neto
-- mayor a cero), se marca el PERIODO como pagado con fun_marcar_nomina_pagada
-- (la función de Nómina: ind_pagado y bloqueo de novedades). Si esa función
-- no existe o falla, se pone ind_pagado = TRUE directamente y se deja un
-- WARNING en el log: el pago del banco ya ocurrió y no se puede perder.
-- No se llama desde PHP.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_aplicar_respuesta_nomina (wano_nomina   tab_nomina.ano_nomina%TYPE,
                                                         wmes_nomina   tab_nomina.mes_nomina%TYPE,
                                                         wval_periodo  tab_nomina.val_periodo%TYPE,
                                                         wid_empleado  tab_nomina.id_empleado%TYPE,
                                                         westado_pago  tab_pagos_nomina.estado_pago%TYPE,
                                                         wfec_pago     tab_pagos_nomina.fec_pago%TYPE) RETURNS VOID AS
$BODY$
BEGIN
    IF westado_pago = 2 THEN
        UPDATE tab_nomina
           SET estado_pago = 2,
               fec_pago    = wfec_pago
         WHERE ano_nomina  = wano_nomina
           AND mes_nomina  = wmes_nomina
           AND val_periodo = wval_periodo
           AND id_empleado = wid_empleado;

        -- ¿Quedó todo el periodo pagado?
        IF NOT EXISTS (SELECT 1 FROM tab_nomina
                        WHERE ano_nomina  = wano_nomina
                          AND mes_nomina  = wmes_nomina
                          AND val_periodo = wval_periodo
                          AND ind_borrado IS NOT TRUE
                          AND val_neto    > 0
                          AND estado_pago <> 2)
           AND EXISTS (SELECT 1 FROM tab_nomina
                        WHERE ano_nomina  = wano_nomina
                          AND mes_nomina  = wmes_nomina
                          AND val_periodo = wval_periodo
                          AND ind_borrado IS NOT TRUE
                          AND ind_pagado  IS NOT TRUE) THEN
            BEGIN
                IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fun_marcar_nomina_pagada') THEN
                    -- Literales enteros: sirven si la función recibe INTEGER o DECIMAL
                    EXECUTE format('SELECT fun_marcar_nomina_pagada(%s, %s, %s)',
                                   wano_nomina::INTEGER, wmes_nomina::INTEGER, wval_periodo::INTEGER);
                ELSE
                    RAISE EXCEPTION 'fun_marcar_nomina_pagada no existe';
                END IF;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Nómina %-%-% pagada por el banco, pero fun_marcar_nomina_pagada falló (%). Se marca ind_pagado directamente.',
                    wano_nomina, wmes_nomina, wval_periodo, SQLERRM;
                UPDATE tab_nomina
                   SET ind_pagado = TRUE
                 WHERE ano_nomina  = wano_nomina
                   AND mes_nomina  = wmes_nomina
                   AND val_periodo = wval_periodo
                   AND ind_borrado IS NOT TRUE;
            END;
        END IF;
    ELSIF westado_pago = 3 THEN
        UPDATE tab_nomina
           SET estado_pago = 3,
               fec_pago    = NULL
         WHERE ano_nomina  = wano_nomina
           AND mes_nomina  = wmes_nomina
           AND val_periodo = wval_periodo
           AND id_empleado = wid_empleado
           AND estado_pago = 1;
    END IF;
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE PAGOS DE NÓMINA
-- Registra la respuesta del banco para UNA línea de un archivo de nómina.
-- El valor sale de la línea del archivo y el banco del encabezado.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_pagos_nomina (wid_archivo_plano  tab_pagos_nomina.id_archivo_plano%TYPE,
                                                    wano_nomina        tab_pagos_nomina.ano_nomina%TYPE,
                                                    wmes_nomina        tab_pagos_nomina.mes_nomina%TYPE,
                                                    wval_periodo       tab_pagos_nomina.val_periodo%TYPE,
                                                    wid_empleado       tab_pagos_nomina.id_empleado%TYPE,
                                                    wfec_pago          tab_pagos_nomina.fec_pago%TYPE,
                                                    westado_pago       tab_pagos_nomina.estado_pago%TYPE,
                                                    wid_codigo         tab_pagos_nomina.id_codigo%TYPE) RETURNS BOOLEAN AS
$BODY$
DECLARE wid_pago        tab_pagos_nomina.id_pago_nomina%TYPE;
        wval_pago       tab_det_archivo_nomina.val_a_pagar%TYPE;
        wid_banco       tab_enc_archivo_plano.id_banco%TYPE;
        wind_generado   tab_enc_archivo_plano.ind_generado%TYPE;
        wfec_generacion tab_enc_archivo_plano.fec_generacion%TYPE;
BEGIN

    IF wid_archivo_plano IS NULL OR wano_nomina IS NULL OR wmes_nomina IS NULL
       OR wval_periodo IS NULL OR wid_empleado IS NULL THEN
        RAISE EXCEPTION 'Archivo plano, periodo y empleado son obligatorios.';
    END IF;

    IF wfec_pago IS NULL THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser nula.';
    END IF;

    IF westado_pago IS NULL OR westado_pago NOT IN (1, 2, 3) THEN
        RAISE EXCEPTION 'El estado % no es válido: debe ser 1 (Pendiente), 2 (Aprobado) o 3 (Rechazado).', westado_pago;
    END IF;

    IF wid_codigo IS NULL THEN
        RAISE EXCEPTION 'El código de respuesta del banco no puede ser nulo.';
    END IF;

-- EL ARCHIVO EXISTE, ES DE NÓMINA Y YA SE GENERÓ
    SELECT id_banco, ind_generado, fec_generacion
      INTO wid_banco, wind_generado, wfec_generacion
      FROM tab_enc_archivo_plano
     WHERE id_archivo_plano = wid_archivo_plano;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El archivo plano % no existe.', wid_archivo_plano;
    END IF;

    IF fun_tipo_archivo_plano(wid_archivo_plano) <> 'NOMINA' THEN
        RAISE EXCEPTION 'El archivo plano % no es de nómina.', wid_archivo_plano;
    END IF;

    IF NOT wind_generado THEN
        RAISE EXCEPTION 'El archivo plano % todavía no ha sido generado; no puede tener respuesta del banco.', wid_archivo_plano;
    END IF;

-- EL EMPLEADO ESTÁ EN ESE ARCHIVO
    SELECT val_a_pagar INTO wval_pago
      FROM tab_det_archivo_nomina
     WHERE id_archivo_plano = wid_archivo_plano
       AND ano_nomina       = wano_nomina
       AND mes_nomina       = wmes_nomina
       AND val_periodo      = wval_periodo
       AND id_empleado      = wid_empleado;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El empleado % no está en el archivo plano %.', wid_empleado, wid_archivo_plano;
    END IF;

-- ESA LÍNEA NO TIENE YA UNA RESPUESTA
    IF EXISTS (SELECT 1 FROM tab_pagos_nomina
                WHERE id_archivo_plano = wid_archivo_plano
                  AND ano_nomina       = wano_nomina
                  AND mes_nomina       = wmes_nomina
                  AND val_periodo      = wval_periodo
                  AND id_empleado      = wid_empleado) THEN
        RAISE EXCEPTION 'El empleado % ya tiene una respuesta registrada en el archivo plano %. Si está pendiente, actualícela.', wid_empleado, wid_archivo_plano;
    END IF;

-- NO ESTÁ YA PAGADO EN ESE PERIODO
    IF westado_pago = 2 AND EXISTS (SELECT 1 FROM tab_pagos_nomina
                                     WHERE ano_nomina  = wano_nomina
                                       AND mes_nomina  = wmes_nomina
                                       AND val_periodo = wval_periodo
                                       AND id_empleado = wid_empleado
                                       AND estado_pago = 2) THEN
        RAISE EXCEPTION 'La nómina del empleado % de %-%, periodo % ya fue pagada.', wid_empleado, wano_nomina, wmes_nomina, wval_periodo;
    END IF;

-- CÓDIGO ACTIVO PARA EL BANCO DEL ARCHIVO
    IF NOT EXISTS (SELECT 1 FROM tab_codigos_respuesta_banco
                    WHERE id_codigo   = wid_codigo
                      AND id_banco    = wid_banco
                      AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El código % no existe o está inactivo para el banco % del archivo plano.', wid_codigo, wid_banco;
    END IF;

-- FECHA: NO FUTURA NI ANTERIOR A LA GENERACIÓN
    IF wfec_pago > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser futura.';
    END IF;

    IF wfec_generacion IS NOT NULL AND wfec_pago < wfec_generacion THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser anterior a la generación del archivo plano (%).', TO_CHAR(wfec_generacion, 'DD/MM/YYYY');
    END IF;

    SELECT COALESCE(MAX(id_pago_nomina), 0) + 1 INTO wid_pago FROM tab_pagos_nomina;

    INSERT INTO tab_pagos_nomina (id_pago_nomina, id_archivo_plano, ano_nomina, mes_nomina, val_periodo, id_empleado,
                                  fec_pago, val_pago, estado_pago, id_codigo, id_banco)
    VALUES                       (wid_pago, wid_archivo_plano, wano_nomina, wmes_nomina, wval_periodo, wid_empleado,
                                  wfec_pago, wval_pago, westado_pago, wid_codigo, wid_banco);

    PERFORM fun_aplicar_respuesta_nomina(wano_nomina, wmes_nomina, wval_periodo, wid_empleado, westado_pago, wfec_pago);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- INTEGRACIÓN CON EL ÁREA FINANCIERA: PAGO DE INVERSIONES
-- Mismo modelo que Nómina: Financiero envía sus cuotas aprobadas, Tesorería
-- las saca en un archivo plano y la respuesta del banco deja cada cuota
-- PAGADA o RECHAZADA en tab_cuotas_inversion (tabla del módulo Financiero).
--
-- El encabezado del archivo es el normal (tab_enc_archivo_plano, sin
-- columnas extra); las líneas van en tab_det_archivo_inversion y las
-- respuestas del banco en tab_pagos_inversion.
--
-- tab_cuotas_inversion.estado_pago
--     0 = SIN ENVIAR     1 = ENVIADA A TESORERÍA (pendiente del banco)
--     2 = PAGADA         3 = RECHAZADA POR EL BANCO (se puede reenviar)
--------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN: ENVIAR CUOTAS DE INVERSIONES A TESORERÍA
-- La llama el botón "Enviar cuotas a Tesorería" del módulo Financiero.
--
--   SELECT fun_enviar_inversiones_tesoreria(CURRENT_DATE);   -- devuelve el id del archivo plano
--
-- - Toma las cuotas APROBADAS, con valor mayor a cero, vencidas hasta la
--   fecha de corte, con estado_pago 0 (sin enviar) o 3 (rechazadas por el
--   banco: se reenvían con la cuenta corregida), de inversiones VIGENTES,
--   RENOVADAS o VENCIDAS.
-- - Desde el envío, la cuota y su inversión no se pueden modificar (triggers
--   del módulo Financiero) hasta que Tesorería devuelva el archivo.
-- - Valida inversor, banco y cuenta de cada cuota; si alguna falla no se
--   envía nada y el mensaje dice cuáles.
-- - Encabezado normal: la primera cuenta activa de la empresa y la próxima
--   fecha de pago válida. Tesorería puede cambiar cuenta, fecha y nombre
--   antes de descargarlo.
-- - Nombre: INVERSION_2026_11_14 (fecha de corte), y _R2, _R3... si ese
--   corte ya se había enviado antes.
-- - Deja las cuotas enviadas en estado_pago = 1.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_enviar_inversiones_tesoreria (wfec_corte  DATE) RETURNS DECIMAL AS
$BODY$

DECLARE wid_archivo_plano   tab_enc_archivo_plano.id_archivo_plano%TYPE;
        wid_empresa         tab_pmtros_grales.id_empresa%TYPE;
        wnom_empresa        tab_pmtros_grales.nom_empresa%TYPE;
        wcta                RECORD;
        wfecha_aplicacion   DATE;
        wnom_base           VARCHAR(30);
        wnom_archivo        tab_enc_archivo_plano.nom_archivo%TYPE;
        wenvios_previos     INTEGER;
        wcantidad           INTEGER;
        werrores            TEXT;
        wcant_errores       INTEGER;

BEGIN

-- VALIDAR PARÁMETROS
    IF wfec_corte IS NULL THEN
        RAISE EXCEPTION 'Indique la fecha de corte: se envían las cuotas aprobadas que vencen hasta ese día.';
    END IF;

-- BLOQUEAR LAS CUOTAS CANDIDATAS: si alguien da doble clic, la segunda
-- llamada espera aquí y después ya no encuentra cuotas pendientes.
    PERFORM 1
       FROM tab_cuotas_inversion
      WHERE ind_aprobada    = TRUE
        AND estado_pago     IN (0, 3)
        AND fec_vencimiento <= wfec_corte
      FOR UPDATE;

-- ¿HAY CUOTAS PARA ENVIAR?
    SELECT COUNT(c.id_cuota) INTO wcantidad
      FROM tab_cuotas_inversion c
      JOIN tab_inversiones      n ON n.id_proyecto = c.id_proyecto AND n.id_inversor = c.id_inversor
     WHERE c.ind_aprobada     = TRUE
       AND c.estado_pago      IN (0, 3)
       AND c.fec_vencimiento  <= wfec_corte
       AND c.val_neto         > 0
       AND n.ind_borrado      = FALSE
       AND n.estado_inversion IN ('VIGENTE', 'RENOVADA', 'VENCIDA');

    IF wcantidad = 0 THEN
        RAISE EXCEPTION 'No hay cuotas de inversiones aprobadas y pendientes de enviar con vencimiento hasta el %.', TO_CHAR(wfec_corte, 'DD/MM/YYYY');
    END IF;

-- VALIDAR LOS DATOS BANCARIOS DE CADA CUOTA (se listan todas las que fallan)
    SELECT COUNT(x.motivo),
           STRING_AGG(x.motivo, '; ' ORDER BY x.motivo)
      INTO wcant_errores, werrores
      FROM (SELECT COALESCE(TRIM(i.nom_inversor), '') || ' (' || c.id_inversor || ', proyecto ' || c.id_proyecto || ', cuota ' || c.id_cuota || '): ' ||
                   CASE
                       WHEN i.id_inversor IS NULL                                 THEN 'no existe en Inversores'
                       WHEN i.ind_borrado OR i.estado_inversor <> 'ACTIVO'        THEN 'el inversor no está activo'
                       WHEN COALESCE(TRIM(i.id_banco), '') = ''                   THEN 'sin banco'
                       WHEN b.id_banco IS NULL                                    THEN 'el banco ' || i.id_banco || ' no existe'
                       WHEN b.ind_borrado OR NOT b.ind_estado                     THEN 'el banco ' || b.nom_banco || ' está inactivo'
                       WHEN COALESCE(i.num_cuenta, '') !~ '^[0-9]{6,20}$'         THEN 'número de cuenta no válido (solo dígitos, 6 a 20)'
                       WHEN COALESCE(i.id_tipo, '') !~ '^[A-Z]{2,5}$'             THEN 'tipo de documento no válido'
                       WHEN LENGTH(TRIM(COALESCE(i.nom_inversor, ''))) < 3        THEN 'nombre del inversor no válido'
                       WHEN c.val_neto > 9999999999                               THEN 'el valor supera el máximo de un pago por archivo plano (9.999.999.999)'
                   END AS motivo
              FROM tab_cuotas_inversion c
              JOIN tab_inversiones      n ON n.id_proyecto = c.id_proyecto AND n.id_inversor = c.id_inversor
              LEFT JOIN tab_inversores  i ON i.id_inversor = c.id_inversor
              LEFT JOIN tab_bancos      b ON b.id_banco    = i.id_banco
             WHERE c.ind_aprobada     = TRUE
               AND c.estado_pago      IN (0, 3)
               AND c.fec_vencimiento  <= wfec_corte
               AND c.val_neto         > 0
               AND n.ind_borrado      = FALSE
               AND n.estado_inversion IN ('VIGENTE', 'RENOVADA', 'VENCIDA')) x
     WHERE x.motivo IS NOT NULL;

    IF wcant_errores > 0 THEN
        RAISE EXCEPTION 'No se enviaron las inversiones: % cuota(s) con datos incompletos. %', wcant_errores, werrores;
    END IF;

-- EMPRESA (Parámetros Generales)
    SELECT id_empresa, nom_empresa
      INTO wid_empresa, wnom_empresa
      FROM tab_pmtros_grales
     WHERE ind_borrado = FALSE
     ORDER BY id_empresa
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay empresa configurada en Parámetros Generales.';
    END IF;

-- CUENTA DE ORIGEN: la primera cuenta activa de la empresa con banco activo
-- (mismo orden que el select de Archivo Plano). Tesorería la puede cambiar.
    SELECT c.cta_empresa, c.id_banco, c.ind_tipocuenta
      INTO wcta
      FROM tab_ctas_empresa c
      JOIN tab_bancos       b ON b.id_banco = c.id_banco
     WHERE c.id_empresa  = wid_empresa
       AND c.ind_borrado = FALSE
       AND b.ind_borrado = FALSE
       AND b.ind_estado  = TRUE
     ORDER BY b.nom_banco, c.cta_empresa
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tesorería no tiene cuentas bancarias activas para pagar las inversiones. Avise a Tesorería.';
    END IF;

-- FECHA DE APLICACIÓN: próximo día de pago que no sea festivo
    IF NOT EXISTS (SELECT 1 FROM tab_pmtros_tescxp WHERE id_empresa = wid_empresa AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'Tesorería no tiene configurados los días de pago (Parámetros de Tesorería). Avise a Tesorería.';
    END IF;

    wfecha_aplicacion := fun_proxima_fecha_pago(wid_empresa, CURRENT_DATE);
    IF wfecha_aplicacion IS NULL THEN
        RAISE EXCEPTION 'No se encontró una fecha de pago válida en los próximos 120 días. Revise Parámetros de Tesorería y Festivos.';
    END IF;

-- NOMBRE: INVERSION_2026_11_14, y _R2, _R3... si ese corte ya se envió antes.
-- El encabezado no guarda la fecha de corte: se cuentan los archivos de
-- inversiones (los que tienen líneas en tab_det_archivo_inversion) con ese nombre.
    wnom_base := 'INVERSION_' || TO_CHAR(wfec_corte, 'YYYY_MM_DD');

    SELECT COUNT(a.nom_archivo) INTO wenvios_previos
      FROM tab_enc_archivo_plano a
     WHERE (a.nom_archivo = wnom_base OR a.nom_archivo LIKE wnom_base || '\_R%')
       AND EXISTS (SELECT 1 FROM tab_det_archivo_inversion d WHERE d.id_archivo_plano = a.id_archivo_plano);

    wnom_archivo := wnom_base || CASE WHEN wenvios_previos > 0 THEN '_R' || (wenvios_previos + 1) ELSE '' END;

-- ENCABEZADO (el mismo de todos los archivos planos)
    LOCK TABLE tab_enc_archivo_plano IN SHARE ROW EXCLUSIVE MODE;   -- el MAX + 1 no se cruza con otro envío

    SELECT COALESCE(MAX(id_archivo_plano), 0) + 1 INTO wid_archivo_plano
      FROM tab_enc_archivo_plano;

    INSERT INTO tab_enc_archivo_plano (id_archivo_plano, nom_archivo, id_empresa, nom_empresa, id_banco,
                                       ind_tipocuenta, cta_empresa, fecha_aplicacion)
    VALUES                            (wid_archivo_plano, wnom_archivo, wid_empresa, TRIM(wnom_empresa), wcta.id_banco,
                                       wcta.ind_tipocuenta, wcta.cta_empresa, wfecha_aplicacion);

-- DETALLE: copia de los datos bancarios del inversor y el neto a pagar
    INSERT INTO tab_det_archivo_inversion (id_archivo_plano, id_proyecto, id_inversor, id_cuota,
                                           id_tipo, nom_inversor, id_banco, ind_tipocuenta, num_cuenta,
                                           val_a_pagar, concepto)
    SELECT wid_archivo_plano, c.id_proyecto, c.id_inversor, c.id_cuota,
           i.id_tipo,
           LEFT(TRIM(i.nom_inversor), 100),
           i.id_banco,
           COALESCE(i.ind_tipocuenta, FALSE),
           i.num_cuenta,
           c.val_neto,
           LEFT('Inversion ' || c.id_proyecto || ' cuota ' || c.id_cuota, 80)
      FROM tab_cuotas_inversion c
      JOIN tab_inversiones      n ON n.id_proyecto = c.id_proyecto AND n.id_inversor = c.id_inversor
      JOIN tab_inversores       i ON i.id_inversor = c.id_inversor
     WHERE c.ind_aprobada     = TRUE
       AND c.estado_pago      IN (0, 3)
       AND c.fec_vencimiento  <= wfec_corte
       AND c.val_neto         > 0
       AND n.ind_borrado      = FALSE
       AND n.estado_inversion IN ('VIGENTE', 'RENOVADA', 'VENCIDA');

-- MARCAR LAS CUOTAS COMO ENVIADAS
    UPDATE tab_cuotas_inversion c
       SET estado_pago      = 1,
           fec_pago         = NULL,
           id_archivo_plano = wid_archivo_plano
      FROM tab_det_archivo_inversion d
     WHERE d.id_archivo_plano = wid_archivo_plano
       AND c.id_proyecto      = d.id_proyecto
       AND c.id_inversor      = d.id_inversor
       AND c.id_cuota         = d.id_cuota;

    RETURN wid_archivo_plano;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN AUXILIAR: REFLEJAR LA RESPUESTA DEL BANCO EN tab_cuotas_inversion
-- 2 = APROBADO  → cuota PAGADA (con la fecha del banco). Si era la última
--                 por pagar, el trigger de Financiero deja la inversión LIQUIDADA.
-- 3 = RECHAZADO → cuota RECHAZADA (Financiero corrige la cuenta y la reenvía)
-- 1 = PENDIENTE → sigue enviada
-- No se llama desde PHP.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_aplicar_respuesta_inversion (wid_proyecto  tab_cuotas_inversion.id_proyecto%TYPE,
                                                            wid_inversor  tab_cuotas_inversion.id_inversor%TYPE,
                                                            wid_cuota     tab_cuotas_inversion.id_cuota%TYPE,
                                                            westado_pago  tab_pagos_inversion.estado_pago%TYPE,
                                                            wfec_pago     tab_pagos_inversion.fec_pago%TYPE) RETURNS VOID AS
$BODY$
BEGIN
    IF westado_pago = 2 THEN
        UPDATE tab_cuotas_inversion
           SET estado_pago = 2,
               fec_pago    = wfec_pago
         WHERE id_proyecto = wid_proyecto
           AND id_inversor = wid_inversor
           AND id_cuota    = wid_cuota;
    ELSIF westado_pago = 3 THEN
        UPDATE tab_cuotas_inversion
           SET estado_pago = 3,
               fec_pago    = NULL
         WHERE id_proyecto = wid_proyecto
           AND id_inversor = wid_inversor
           AND id_cuota    = wid_cuota
           AND estado_pago = 1;
    END IF;
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE PAGOS DE INVERSIONES
-- Registra la respuesta del banco para UNA línea de un archivo de inversiones.
-- El valor sale de la línea del archivo y el banco del encabezado.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_pagos_inversion (wid_archivo_plano  tab_pagos_inversion.id_archivo_plano%TYPE,
                                                       wid_proyecto       tab_pagos_inversion.id_proyecto%TYPE,
                                                       wid_inversor       tab_pagos_inversion.id_inversor%TYPE,
                                                       wid_cuota          tab_pagos_inversion.id_cuota%TYPE,
                                                       wfec_pago          tab_pagos_inversion.fec_pago%TYPE,
                                                       westado_pago       tab_pagos_inversion.estado_pago%TYPE,
                                                       wid_codigo         tab_pagos_inversion.id_codigo%TYPE) RETURNS BOOLEAN AS
$BODY$
DECLARE wid_pago        tab_pagos_inversion.id_pago_inversion%TYPE;
        wval_pago       tab_det_archivo_inversion.val_a_pagar%TYPE;
        wid_banco       tab_enc_archivo_plano.id_banco%TYPE;
        wind_generado   tab_enc_archivo_plano.ind_generado%TYPE;
        wfec_generacion tab_enc_archivo_plano.fec_generacion%TYPE;
BEGIN

    IF wid_archivo_plano IS NULL OR wid_proyecto IS NULL OR wid_inversor IS NULL OR wid_cuota IS NULL THEN
        RAISE EXCEPTION 'Archivo plano, proyecto, inversor y cuota son obligatorios.';
    END IF;

    IF wfec_pago IS NULL THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser nula.';
    END IF;

    IF westado_pago IS NULL OR westado_pago NOT IN (1, 2, 3) THEN
        RAISE EXCEPTION 'El estado % no es válido: debe ser 1 (Pendiente), 2 (Aprobado) o 3 (Rechazado).', westado_pago;
    END IF;

    IF wid_codigo IS NULL THEN
        RAISE EXCEPTION 'El código de respuesta del banco no puede ser nulo.';
    END IF;

-- EL ARCHIVO EXISTE, ES DE INVERSIONES Y YA SE GENERÓ
    SELECT id_banco, ind_generado, fec_generacion
      INTO wid_banco, wind_generado, wfec_generacion
      FROM tab_enc_archivo_plano
     WHERE id_archivo_plano = wid_archivo_plano;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El archivo plano % no existe.', wid_archivo_plano;
    END IF;

    IF fun_tipo_archivo_plano(wid_archivo_plano) <> 'INVERSION' THEN
        RAISE EXCEPTION 'El archivo plano % no es de inversiones.', wid_archivo_plano;
    END IF;

    IF NOT wind_generado THEN
        RAISE EXCEPTION 'El archivo plano % todavía no ha sido generado; no puede tener respuesta del banco.', wid_archivo_plano;
    END IF;

-- LA CUOTA ESTÁ EN ESE ARCHIVO
    SELECT val_a_pagar INTO wval_pago
      FROM tab_det_archivo_inversion
     WHERE id_archivo_plano = wid_archivo_plano
       AND id_proyecto      = wid_proyecto
       AND id_inversor      = wid_inversor
       AND id_cuota         = wid_cuota;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuota % del inversor % (proyecto %) no está en el archivo plano %.', wid_cuota, wid_inversor, wid_proyecto, wid_archivo_plano;
    END IF;

-- ESA LÍNEA NO TIENE YA UNA RESPUESTA
    IF EXISTS (SELECT 1 FROM tab_pagos_inversion
                WHERE id_archivo_plano = wid_archivo_plano
                  AND id_proyecto      = wid_proyecto
                  AND id_inversor      = wid_inversor
                  AND id_cuota         = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % del inversor % ya tiene una respuesta registrada en el archivo plano %. Si está pendiente, actualícela.', wid_cuota, wid_inversor, wid_archivo_plano;
    END IF;

-- NO ESTÁ YA PAGADA
    IF westado_pago = 2 AND EXISTS (SELECT 1 FROM tab_pagos_inversion
                                     WHERE id_proyecto = wid_proyecto
                                       AND id_inversor = wid_inversor
                                       AND id_cuota    = wid_cuota
                                       AND estado_pago = 2) THEN
        RAISE EXCEPTION 'La cuota % del inversor % (proyecto %) ya fue pagada.', wid_cuota, wid_inversor, wid_proyecto;
    END IF;

-- CÓDIGO ACTIVO PARA EL BANCO DEL ARCHIVO
    IF NOT EXISTS (SELECT 1 FROM tab_codigos_respuesta_banco
                    WHERE id_codigo   = wid_codigo
                      AND id_banco    = wid_banco
                      AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El código % no existe o está inactivo para el banco % del archivo plano.', wid_codigo, wid_banco;
    END IF;

-- FECHA: NO FUTURA NI ANTERIOR A LA GENERACIÓN
    IF wfec_pago > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser futura.';
    END IF;

    IF wfec_generacion IS NOT NULL AND wfec_pago < wfec_generacion THEN
        RAISE EXCEPTION 'La fecha de pago no puede ser anterior a la generación del archivo plano (%).', TO_CHAR(wfec_generacion, 'DD/MM/YYYY');
    END IF;

    SELECT COALESCE(MAX(id_pago_inversion), 0) + 1 INTO wid_pago FROM tab_pagos_inversion;

    INSERT INTO tab_pagos_inversion (id_pago_inversion, id_archivo_plano, id_proyecto, id_inversor, id_cuota,
                                     fec_pago, val_pago, estado_pago, id_codigo, id_banco)
    VALUES                          (wid_pago, wid_archivo_plano, wid_proyecto, wid_inversor, wid_cuota,
                                     wfec_pago, wval_pago, westado_pago, wid_codigo, wid_banco);

    PERFORM fun_aplicar_respuesta_inversion(wid_proyecto, wid_inversor, wid_cuota, westado_pago, wfec_pago);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------------------------------------------------------------
-- SEGURIDAD DE PAGOS
--------------------------------------------------------------------------------------------------------------------------------------
-- Usuario del ERP que hace la operación: el mismo que usa fun_audit_trail
-- (src/config.php lo pone en myapp.user_id con $_SESSION['id_usuario']).
-- NULL si la conexión no trae usuario (por ejemplo, un script ejecutado a mano).
CREATE OR REPLACE FUNCTION fun_usuario_erp() RETURNS VARCHAR AS
$BODY$
DECLARE wid_usuario VARCHAR;
BEGIN
    wid_usuario := NULLIF(TRIM(COALESCE(current_setting('myapp.user_id', TRUE), '')), '');
    IF wid_usuario = '0' THEN
        RETURN NULL;
    END IF;
    RETURN wid_usuario;
END;
$BODY$
LANGUAGE PLPGSQL STABLE;


-- Módulo de Tesorería en tab_menus (menú de primer nivel "Tesorería y Cuentas por Pagar")
CREATE OR REPLACE FUNCTION fun_id_modulo_tesoreria() RETURNS VARCHAR AS
$BODY$
BEGIN
    RETURN CAST('4' AS VARCHAR);
END;
$BODY$
LANGUAGE PLPGSQL IMMUTABLE;


-- ¿El usuario es el líder del área de Tesorería (o administrador)?
-- Igual que Gestión Humana: responsable (tab_areas.id_responsable) del área
-- que dirige el módulo (tab_area_modulo). Usa fun_es_jefe_modulo de
-- fun_generales.sql. Solo el líder entra a Archivo plano, Historial de pagos
-- y Bancos por proveedor (acceso_tesoreria.php).
CREATE OR REPLACE FUNCTION fun_es_lider_tesoreria(wid_usuario VARCHAR) RETURNS BOOLEAN AS
$BODY$
BEGIN
    RETURN COALESCE(fun_es_jefe_modulo(CAST(wid_usuario AS VARCHAR), fun_id_modulo_tesoreria()), FALSE);
END;
$BODY$
LANGUAGE PLPGSQL STABLE;


-- Registra una descarga del archivo plano en tab_descargas_archivo_plano.
-- La PRIMERA guarda la "foto" en el encabezado (cant_lineas_gen, val_total_gen):
-- es lo que se compara con el resumen del lote del portal del banco. Las
-- siguientes se comparan contra esa foto. Devuelve el número de descarga, si
-- coincide con la foto y la foto guardada.
CREATE OR REPLACE FUNCTION fun_registrar_descarga_archivo (wid_archivo_plano  tab_enc_archivo_plano.id_archivo_plano%TYPE,
                                                           wcant_lineas       DECIMAL,
                                                           wval_total         DECIMAL,
                                                           wip_conexion       VARCHAR)
RETURNS TABLE (num_descarga DECIMAL, ind_coincide BOOLEAN, cant_lineas_gen DECIMAL, val_total_gen DECIMAL) AS
$BODY$
DECLARE wenc        RECORD;
        wnum        DECIMAL;
        wcoincide   BOOLEAN;
BEGIN
    IF wid_archivo_plano IS NULL OR wcant_lineas IS NULL OR wval_total IS NULL THEN
        RAISE EXCEPTION 'Faltan datos para registrar la descarga del archivo plano.';
    END IF;

    -- FOR UPDATE: dos descargas al mismo tiempo no pueden quedar con el mismo número
    SELECT e.cant_lineas_gen, e.val_total_gen
      INTO wenc
      FROM tab_enc_archivo_plano e
     WHERE e.id_archivo_plano = wid_archivo_plano
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El archivo plano % no existe.', wid_archivo_plano;
    END IF;

    IF wenc.cant_lineas_gen IS NULL THEN
        -- Primera descarga: se toma la foto
        UPDATE tab_enc_archivo_plano e
           SET cant_lineas_gen = wcant_lineas,
               val_total_gen   = wval_total
         WHERE e.id_archivo_plano = wid_archivo_plano;
        wcoincide := TRUE;
        wenc.cant_lineas_gen := wcant_lineas;
        wenc.val_total_gen   := wval_total;
    ELSE
        wcoincide := (wenc.cant_lineas_gen = wcant_lineas
                      AND wenc.val_total_gen = wval_total);
    END IF;

    SELECT COALESCE(MAX(d.num_descarga), 0) + 1
      INTO wnum
      FROM tab_descargas_archivo_plano d
     WHERE d.id_archivo_plano = wid_archivo_plano;

    INSERT INTO tab_descargas_archivo_plano (id_archivo_plano, num_descarga, id_usuario, ip_conexion,
                                             cant_lineas, val_total, ind_coincide)
    VALUES (wid_archivo_plano, wnum, fun_usuario_erp(), LEFT(wip_conexion, 45),
            wcant_lineas, wval_total, wcoincide);

    RETURN QUERY SELECT wnum, wcoincide, wenc.cant_lineas_gen, wenc.val_total_gen;
END;
$BODY$
LANGUAGE PLPGSQL;


-- Registra una INCONSISTENCIA de la respuesta del banco ("alerta roja"):
-- una línea cuya cuenta, valor o documento no coincide con lo que tenía el
-- ERP. Esa línea NO se da por pagada. El usuario y la fecha los pone
-- trg_usuario_inconsistencia (triggers_tescxp.sql).
CREATE OR REPLACE FUNCTION fun_insert_inconsistencia_respuesta (wid_archivo_plano   tab_inconsistencias_respuesta.id_archivo_plano%TYPE,
                                                                wnum_linea          tab_inconsistencias_respuesta.num_linea%TYPE,
                                                                wnom_beneficiario   VARCHAR,
                                                                wnom_campo          tab_inconsistencias_respuesta.nom_campo%TYPE,
                                                                wval_banco          VARCHAR,
                                                                wval_erp            VARCHAR,
                                                                westado_respuesta   VARCHAR) RETURNS BOOLEAN AS
$BODY$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tab_enc_archivo_plano WHERE id_archivo_plano = wid_archivo_plano) THEN
        RAISE EXCEPTION 'El archivo plano % no existe.', wid_archivo_plano;
    END IF;

    IF wnom_campo NOT IN ('CUENTA', 'VALOR', 'DOCUMENTO', 'TOTAL') THEN
        RAISE EXCEPTION 'Dato de inconsistencia no válido: %.', wnom_campo;
    END IF;

    INSERT INTO tab_inconsistencias_respuesta (id_archivo_plano, num_linea, nom_beneficiario, nom_campo,
                                               val_banco, val_erp, estado_respuesta)
    VALUES (wid_archivo_plano, COALESCE(wnum_linea, 0), LEFT(wnom_beneficiario, 80), wnom_campo,
            LEFT(wval_banco, 40), LEFT(wval_erp, 40), LEFT(westado_respuesta, 10));

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;


-- Compara la suma que respondió el banco para un archivo con la "foto" de la
-- primera descarga. Si el banco respondió por MÁS dinero (alguien agregó
-- pagos o subió valores), registra una inconsistencia TOTAL y devuelve TRUE.
-- Si no hay foto (el archivo se descargó antes de existir este control) no
-- compara y devuelve FALSE.
CREATE OR REPLACE FUNCTION fun_validar_total_respuesta (wid_archivo_plano  tab_enc_archivo_plano.id_archivo_plano%TYPE,
                                                        wsuma_banco        DECIMAL) RETURNS BOOLEAN AS
$BODY$
DECLARE wtotal_foto tab_enc_archivo_plano.val_total_gen%TYPE;
BEGIN
    SELECT val_total_gen INTO wtotal_foto
      FROM tab_enc_archivo_plano
     WHERE id_archivo_plano = wid_archivo_plano;

    IF wtotal_foto IS NULL OR wsuma_banco IS NULL OR wsuma_banco <= wtotal_foto + 0.5 THEN
        RETURN FALSE;
    END IF;

    PERFORM fun_insert_inconsistencia_respuesta(wid_archivo_plano, 0, '(todo el archivo)', 'TOTAL',
                                                TO_CHAR(wsuma_banco, 'FM99999999999999'),
                                                TO_CHAR(wtotal_foto, 'FM99999999999999'), '');
    RETURN TRUE;
END;
$BODY$
LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------------------------------------------------------------
-- CREACIONES COMPLETAS (encabezado + detalle en UNA sola llamada)
--------------------------------------------------------------------------------------------------------------------------------------
-- Antes el PHP abría una transacción, insertaba el encabezado, buscaba su id
-- e insertaba cada línea. Ahora todo lo hace la base de datos en una sola
-- función: si cualquier línea falla, PostgreSQL deshace TODO (no queda un
-- encabezado sin detalle). El detalle llega como un arreglo JSON.

-- Crea un archivo plano de proveedores con sus líneas. Devuelve su id.
-- wdetalle: [{"id_cronograma":..,"id_factura":..,"id_cuota":..,"id_tipo":"..",
--             "id_proveedor":"..","nom_tercero":"..","id_banco":"..",
--             "ind_tipocuenta":true|false,"cta_proveedor":"..","concepto":".."}, ...]
CREATE OR REPLACE FUNCTION fun_crear_archivo_plano (wnom_archivo        tab_enc_archivo_plano.nom_archivo%TYPE,
                                                    wid_empresa         tab_enc_archivo_plano.id_empresa%TYPE,
                                                    wnom_empresa        tab_enc_archivo_plano.nom_empresa%TYPE,
                                                    wid_banco           tab_enc_archivo_plano.id_banco%TYPE,
                                                    wind_tipocuenta     tab_enc_archivo_plano.ind_tipocuenta%TYPE,
                                                    wcta_empresa        tab_enc_archivo_plano.cta_empresa%TYPE,
                                                    wfecha_aplicacion   tab_enc_archivo_plano.fecha_aplicacion%TYPE,
                                                    wdetalle            JSONB) RETURNS DECIMAL AS
$BODY$
DECLARE wid_archivo_plano   tab_enc_archivo_plano.id_archivo_plano%TYPE;
        wlinea              JSONB;
BEGIN
    IF wdetalle IS NULL OR jsonb_typeof(wdetalle) <> 'array' OR jsonb_array_length(wdetalle) = 0 THEN
        RAISE EXCEPTION 'El archivo plano debe tener al menos un pago.';
    END IF;

    PERFORM fun_insert_enc_archivo_plano(wnom_archivo, wid_empresa, wnom_empresa, wid_banco,
                                         wind_tipocuenta, wcta_empresa, wfecha_aplicacion);

    -- El encabezado recién creado (mismo criterio que usaba el PHP)
    SELECT MAX(id_archivo_plano)
      INTO wid_archivo_plano
      FROM tab_enc_archivo_plano
     WHERE nom_archivo  = wnom_archivo
       AND id_empresa   = wid_empresa
       AND cta_empresa  = wcta_empresa
       AND ind_generado = FALSE;

    IF wid_archivo_plano IS NULL THEN
        RAISE EXCEPTION 'No se pudo recuperar el encabezado del archivo plano recién creado.';
    END IF;

    FOR wlinea IN SELECT * FROM jsonb_array_elements(wdetalle) LOOP
        PERFORM fun_insert_det_archivo_plano(wid_archivo_plano,
                                             (wlinea->>'id_cronograma')::DECIMAL,
                                             (wlinea->>'id_factura')::DECIMAL,
                                             (wlinea->>'id_cuota')::DECIMAL,
                                             wlinea->>'id_tipo',
                                             wlinea->>'id_proveedor',
                                             wlinea->>'nom_tercero',
                                             wlinea->>'id_banco',
                                             (wlinea->>'ind_tipocuenta')::BOOLEAN,
                                             wlinea->>'cta_proveedor',
                                             LEFT(wlinea->>'concepto', 80));
    END LOOP;

    RETURN wid_archivo_plano;
END;
$BODY$
LANGUAGE PLPGSQL;


-- Crea un cronograma de pagos con sus cuotas. Devuelve su id.
-- wcuotas: [{"id_factura":..,"id_cuota":..}, ...]
CREATE OR REPLACE FUNCTION fun_crear_cronograma (wnom_cronograma     tab_enc_cronopagos.nom_cronograma%TYPE,
                                                 wfec_programacion   tab_enc_cronopagos.fec_programacion%TYPE,
                                                 wcuotas             JSONB) RETURNS DECIMAL AS
$BODY$
DECLARE wid_cronograma  tab_enc_cronopagos.id_cronograma%TYPE;
        wcuota          JSONB;
BEGIN
    IF wcuotas IS NULL OR jsonb_typeof(wcuotas) <> 'array' OR jsonb_array_length(wcuotas) = 0 THEN
        RAISE EXCEPTION 'Seleccione al menos una cuota para el cronograma.';
    END IF;

    PERFORM fun_insert_enc_cronopagos(wnom_cronograma, wfec_programacion);

    -- El cronograma recién creado (mismo criterio que usaba el PHP)
    SELECT MAX(id_cronograma) INTO wid_cronograma FROM tab_enc_cronopagos;

    FOR wcuota IN SELECT * FROM jsonb_array_elements(wcuotas) LOOP
        PERFORM fun_insert_det_cronopagos(wid_cronograma,
                                          (wcuota->>'id_factura')::DECIMAL,
                                          (wcuota->>'id_cuota')::DECIMAL);
    END LOOP;

    RETURN wid_cronograma;
END;
$BODY$
LANGUAGE PLPGSQL;
