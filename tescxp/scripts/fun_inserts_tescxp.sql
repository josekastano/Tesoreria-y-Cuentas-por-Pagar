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
              WHERE proname IN ('fun_insert_enc_archivo_plano',
                                'fun_insert_det_archivo_plano',
                                'fun_insert_motivos_rechazo',
                                'fun_insert_pagos_cxp',
                                'fun_aplicar_pago_aprobado') LOOP
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE DETALLE DE CAJA MENOR
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_det_caja_menor (wid_caja_menor        tab_det_caja_menor.id_caja_menor%TYPE,
                                                      wconcepto             tab_det_caja_menor.concepto%TYPE,
                                                      wval_movimiento       tab_det_caja_menor.val_movimiento%TYPE,
                                                      wfecha_movimiento     tab_det_caja_menor.fecha_movimiento%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wdisponible     tab_enc_caja_menor.monto_disponible%TYPE;
DECLARE wid_movimiento  tab_det_caja_menor.id_movimiento%TYPE;

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

-- VALIDAR QUE EL CONCEPTO NO SEA VACÍO
    IF wconcepto = '' THEN
        RAISE EXCEPTION 'El concepto no puede estar vacío.';
    END IF;

-- VALIDAR QUE EL CONCEPTO TENGA ENTRE 1 Y 200 CARACTERES
    IF LENGTH(wconcepto) < 3 OR LENGTH(wconcepto) > 200 THEN
        RAISE EXCEPTION 'El concepto debe tener entre 1 y 200 caracteres.';
    END IF;

-- VALIDAR QUE EL VALOR DEL MOVIMIENTO SEA MAYOR A 0 Y MENOR O IGUAL A 99999999
    IF wval_movimiento <= 0 OR wval_movimiento > 99999999 THEN
        RAISE EXCEPTION 'El valor del movimiento debe estar entre 1 y 99.999.999.';
    END IF;

-- VALIDAR QUE HAY SALDO SUFICIENTE EN LA CAJA MENOR
    SELECT monto_disponible INTO wdisponible FROM tab_enc_caja_menor WHERE id_caja_menor = wid_caja_menor;
    IF wval_movimiento > wdisponible THEN
        RAISE EXCEPTION 'El valor del movimiento (%) supera el monto disponible en la caja menor (%).', wval_movimiento, wdisponible;
    END IF;

-- SI TODO VA BIEN, SE INSERTA EN tab_det_caja_menor
    SELECT COALESCE(MAX(id_movimiento), 0) + 1 INTO wid_movimiento
    FROM tab_det_caja_menor;

    INSERT INTO tab_det_caja_menor (id_caja_menor, id_movimiento, concepto, val_movimiento, fecha_movimiento)
    VALUES                         (wid_caja_menor, wid_movimiento, wconcepto, wval_movimiento, wfecha_movimiento);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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

-- SI TODO VA BIEN, SE INSERTA EN tab_det_cronopagos
    INSERT INTO tab_det_cronopagos (id_cronograma, id_factura, id_cuota)
    VALUES (wid_cronograma, wid_factura, wid_cuota);

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE TIPOS DE PAGO
-- NOTA: El ID va de 1 a 9 (DECIMAL(1,0)) y lo elige el usuario. El nombre se guarda en
--       mayúsculas y no se puede repetir (sin importar mayúsculas/minúsculas).
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_tipos_pago (wid_tipo_pago     tab_tipos_pago.id_tipo_pago%TYPE,
                                                  wnom_tipo_pago    tab_tipos_pago.nom_tipo_pago%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE LOS CAMPOS NO SEAN NULOS
    IF wid_tipo_pago IS NULL THEN
        RAISE EXCEPTION 'El ID del tipo de pago no puede ser nulo.';
    END IF;

    IF wnom_tipo_pago IS NULL THEN
        RAISE EXCEPTION 'El nombre del tipo de pago no puede ser nulo.';
    END IF;

-- VALIDAR RANGO DEL ID (mismo CHECK de la tabla)
    IF wid_tipo_pago < 1 OR wid_tipo_pago > 9 THEN
        RAISE EXCEPTION 'El ID del tipo de pago debe estar entre 1 y 9.';
    END IF;

-- VALIDAR LONGITUD DEL NOMBRE (mismo CHECK de la tabla)
    IF LENGTH(TRIM(wnom_tipo_pago)) < 1 OR LENGTH(TRIM(wnom_tipo_pago)) > 15 THEN
        RAISE EXCEPTION 'El nombre del tipo de pago debe tener entre 1 y 15 caracteres.';
    END IF;

-- VALIDAR QUE EL ID NO EXISTA (si está inactivo, se debe reactivar en vez de crearlo)
    IF EXISTS (SELECT 1 FROM tab_tipos_pago WHERE id_tipo_pago = wid_tipo_pago AND ind_borrado = TRUE) THEN
        RAISE EXCEPTION 'El ID % ya existe y está inactivo; actívelo en lugar de crearlo de nuevo.', wid_tipo_pago;
    END IF;

    IF EXISTS (SELECT 1 FROM tab_tipos_pago WHERE id_tipo_pago = wid_tipo_pago) THEN
        RAISE EXCEPTION 'El ID % ya está en uso.', wid_tipo_pago;
    END IF;

-- VALIDAR QUE EL NOMBRE NO ESTÉ REPETIDO
    IF EXISTS (SELECT 1 FROM tab_tipos_pago WHERE UPPER(nom_tipo_pago) = UPPER(TRIM(wnom_tipo_pago))) THEN
        RAISE EXCEPTION 'Ya existe un tipo de pago con el nombre %.', UPPER(TRIM(wnom_tipo_pago));
    END IF;

-- SI TODO VA BIEN, SE INSERTA (ind_borrado QUEDA EN FALSE POR EL DEFAULT)
    INSERT INTO tab_tipos_pago (id_tipo_pago, nom_tipo_pago)
    VALUES                     (wid_tipo_pago, UPPER(TRIM(wnom_tipo_pago)));

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE ENCABEZADO DE ARCHIVO PLANO
--    El encabezado ya no lleva id_cronograma: lleva la cuenta de origen de la
--    empresa, el tipo de pago y la fecha de aplicación. Un archivo puede tener
--    cuotas de varios cronogramas (van en el detalle).
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_insert_enc_archivo_plano (wnom_archivo        tab_enc_archivo_plano.nom_archivo%TYPE,
                                                         wid_empresa         tab_enc_archivo_plano.id_empresa%TYPE,
                                                         wnom_empresa        tab_enc_archivo_plano.nom_empresa%TYPE,
                                                         wid_banco           tab_enc_archivo_plano.id_banco%TYPE,
                                                         wind_tipocuenta     tab_enc_archivo_plano.ind_tipocuenta%TYPE,
                                                         wcta_empresa        tab_enc_archivo_plano.cta_empresa%TYPE,
                                                         wfecha_aplicacion   tab_enc_archivo_plano.fecha_aplicacion%TYPE,
                                                         wid_tipo_pago       tab_enc_archivo_plano.id_tipo_pago%TYPE) RETURNS BOOLEAN AS
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

    IF wid_tipo_pago IS NULL THEN
        RAISE EXCEPTION 'El tipo de pago no puede ser nulo.';
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

-- VALIDAR QUE EL TIPO DE PAGO EXISTA Y ESTÉ ACTIVO
    IF NOT EXISTS (SELECT 1 FROM tab_tipos_pago WHERE id_tipo_pago = wid_tipo_pago AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El tipo de pago % no existe o está inactivo.', wid_tipo_pago;
    END IF;

-- SI TODO VA BIEN, SE INSERTA (fec_generacion queda NULL e ind_generado en FALSE)
    SELECT COALESCE(MAX(id_archivo_plano), 0) + 1 INTO wid_archivo_plano
      FROM tab_enc_archivo_plano;

    INSERT INTO tab_enc_archivo_plano (id_archivo_plano, nom_archivo, id_empresa, nom_empresa, id_banco,
                                       ind_tipocuenta, cta_empresa, fecha_aplicacion, id_tipo_pago)
    VALUES                            (wid_archivo_plano, TRIM(wnom_archivo), wid_empresa, TRIM(wnom_empresa), wid_banco,
                                       wind_tipocuenta, wcta_empresa, wfecha_aplicacion, wid_tipo_pago);

    RETURN TRUE;

EXCEPTION
    -- Campo obligatorio en NULL: se agrega qué tabla y columna, porque el
    -- mensaje general ("Un campo obligatorio está vacío") no lo dice.
    WHEN not_null_violation THEN
        GET STACKED DIAGNOSTICS wtabla_err = TABLE_NAME, wcolumna_err = COLUMN_NAME;
        RAISE EXCEPTION 'ERROR: % (%.%)', public.fun_mensaje_error(SQLSTATE, SQLERRM), wtabla_err, wcolumna_err;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE INSERT DE DETALLE DE ARCHIVO PLANO
-- NOTA: Una cuota puede volver a un archivo plano solo si todas sus líneas
--       anteriores tienen un pago RECHAZADO (3).
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

-- VALIDAR QUE EL CRONOGRAMA EXISTA, ESTÉ ACTIVO Y PENDIENTE
    IF NOT EXISTS (SELECT 1 FROM tab_enc_cronopagos
                    WHERE id_cronograma = wid_cronograma
                      AND ind_borrado   = FALSE
                      AND ind_estado    = FALSE) THEN
        RAISE EXCEPTION 'El cronograma % no existe, está inactivo o ya fue pagado.', wid_cronograma;
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
        RAISE EXCEPTION 'ERROR: % (%.%)', public.fun_mensaje_error(SQLSTATE, SQLERRM), wtabla_err, wcolumna_err;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
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
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN AUXILIAR: EFECTOS DE UN PAGO APROBADO
-- La usan fun_insert_pagos_cxp y fun_update_pagos_cxp cuando el pago queda
-- en 2 (APROBADO). No se llama desde PHP.
--   1) Marca la cuota como pagada (trg_actualizar_saldo_factura descuenta el
--      saldo de la factura y trg_actualizar_saldo_proveedor la deuda).
--   2) Cierra el cronograma si ya no le quedan cuotas sin pagar.
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

    UPDATE tab_enc_cronopagos e
    SET    ind_estado = TRUE
    WHERE  e.id_cronograma = wid_cronograma
      AND  e.ind_estado    = FALSE
      AND  NOT EXISTS (SELECT 1
                         FROM tab_det_cronopagos d
                         JOIN tab_cuotasxfactura c ON c.id_factura = d.id_factura
                                                  AND c.id_cuota   = d.id_cuota
                        WHERE d.id_cronograma = e.id_cronograma
                          AND c.ind_pagada    = FALSE);
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

-- SI QUEDÓ APROBADO: CUOTA PAGADA Y, SI ES LA ÚLTIMA, CRONOGRAMA CERRADO
    IF westado_pago = 2 THEN
        PERFORM fun_aplicar_pago_aprobado(wid_factura, wid_cuota, wid_cronograma);
    END IF;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

