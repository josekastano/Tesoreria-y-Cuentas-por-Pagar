--------------------------------------------------------------------------------------------------------------------------------------
-- LIMPIEZA DE VERSIONES ANTERIORES
-- fun_delete_motivos_rechazo ya no existe (la tabla pasó a tab_codigos_respuesta_banco).
--------------------------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fun_delete_motivos_rechazo(NUMERIC);

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE LÓGICO DE FESTIVOS
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_festivos (wid_festivo     tab_festivos.id_festivo%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID DEL FESTIVO NO SEA NULO
    IF wid_festivo IS NULL THEN
        RAISE EXCEPTION 'El ID del festivo no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL FESTIVO EXISTA Y NO ESTÉ YA BORRADO
    IF NOT EXISTS (SELECT 1 FROM tab_festivos WHERE id_festivo = wid_festivo AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El festivo % no existe o ya se encuentra inactivo.', wid_festivo;
    END IF;

-- SI TODO VA BIEN, SE BORRA LÓGICAMENTE EN tab_festivos
    UPDATE tab_festivos
    SET    ind_borrado = TRUE
    WHERE  id_festivo  = wid_festivo;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE CIERRE DE ENCABEZADO DE CAJA MENOR 
--------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE CIERRE (DELETE LÓGICO) DE ENCABEZADO DE CAJA MENOR
-- NOTA: No se elimina físicamente el registro. Se marca la caja como cerrada
--       (fecha_cierre = CURRENT_DATE, ind_estado_caja_m = FALSE). Solo se
--       permite cerrar una caja que no tenga movimientos sin resolver, es
--       decir, movimientos en estado Pendiente (1) o Aprobado (2) que aún
--       no hayan sido Reembolsados (3) a la caja.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_enc_caja_menor (wid_caja_menor      tab_enc_caja_menor.id_caja_menor%TYPE) RETURNS BOOLEAN AS
$BODY$

DECLARE wmovs_sin_resolver  INTEGER;

BEGIN

-- VALIDAR QUE EL ID DE LA CAJA MENOR NO SEA NULO
    IF wid_caja_menor IS NULL THEN
        RAISE EXCEPTION 'El ID de la caja menor no puede ser nulo.';
    END IF;

-- VALIDAR QUE LA CAJA MENOR EXISTA, ESTÉ ACTIVA Y NO ESTÉ CERRADA
    IF NOT EXISTS (SELECT 1 FROM tab_enc_caja_menor WHERE id_caja_menor = wid_caja_menor AND ind_estado_caja_m = TRUE) THEN
        RAISE EXCEPTION 'La caja menor % no existe, está inactiva o ya fue cerrada.', wid_caja_menor;
    END IF;

-- VALIDAR QUE NO EXISTAN MOVIMIENTOS SIN RESOLVER (PENDIENTES O APROBADOS, AÚN NO REEMBOLSADOS)
    SELECT COUNT(id_movimiento) INTO wmovs_sin_resolver
    FROM   tab_det_caja_menor
    WHERE  id_caja_menor = wid_caja_menor AND ind_estado IN (1, 2);

    IF wmovs_sin_resolver > 0 THEN
        RAISE EXCEPTION 'La caja menor % tiene % movimiento(s) sin reembolsar. Debe reembolsarlos antes de cerrar la caja.', wid_caja_menor, wmovs_sin_resolver;
    END IF;

-- SI TODO VA BIEN, SE CIERRA LA CAJA EN tab_enc_caja_menor
    UPDATE tab_enc_caja_menor
    SET    fecha_cierre      = CURRENT_DATE,
           ind_estado_caja_m = FALSE
    WHERE  id_caja_menor     = wid_caja_menor;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE LÓGICO DE CUENTAS DE LA EMPRESA
-- NOTA: No se permite borrar si la cuenta está siendo usada en un archivo plano
--       que aún no ha sido generado (ind_generado = FALSE).
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_ctas_empresa (wid_empresa     tab_ctas_empresa.id_empresa%TYPE,
                                                    wcta_empresa    tab_ctas_empresa.cta_empresa%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

    IF wid_empresa IS NULL THEN
        RAISE EXCEPTION 'El ID de la empresa no puede ser nulo.';
    END IF;

    IF wcta_empresa IS NULL THEN
        RAISE EXCEPTION 'El número de cuenta de la empresa no puede ser nulo.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tab_ctas_empresa WHERE id_empresa = wid_empresa AND cta_empresa = wcta_empresa AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'La cuenta % de la empresa % no existe o ya se encuentra inactiva.', wcta_empresa, wid_empresa;
    END IF;

-- VALIDAR QUE LA CUENTA NO SEA LA DE ORIGEN DE UN ARCHIVO PLANO PENDIENTE (NO GENERADO)
    IF EXISTS (SELECT 1 FROM tab_enc_archivo_plano
                WHERE id_empresa   = wid_empresa
                  AND cta_empresa  = wcta_empresa
                  AND ind_generado = FALSE) THEN
        RAISE EXCEPTION 'La cuenta % de la empresa % está siendo usada en un archivo plano pendiente y no puede ser borrada.', wcta_empresa, wid_empresa;
    END IF;

    UPDATE tab_ctas_empresa
    SET    ind_borrado  = TRUE
    WHERE  id_empresa   = wid_empresa AND cta_empresa = wcta_empresa;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE LÓGICO DE BANCOS POR PROVEEDORES
-- NOTA: No se permite borrar si la cuenta está siendo usada en un archivo plano
--       que aún no ha sido generado (ind_generado = FALSE).
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_bancoxprov (wid_proveedor     tab_bancoxprov.id_proveedor%TYPE,
                                                   wcta_proveedor    tab_bancoxprov.cta_proveedor%TYPE) RETURNS BOOLEAN AS
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

-- VALIDAR QUE LA CUENTA EXISTA Y NO ESTÉ YA BORRADA
    IF NOT EXISTS (SELECT 1 FROM tab_bancoxprov WHERE id_proveedor = wid_proveedor AND cta_proveedor = wcta_proveedor AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'La cuenta % del proveedor % no existe o ya se encuentra inactiva.', wcta_proveedor, wid_proveedor;
    END IF;

-- VALIDAR QUE LA CUENTA NO ESTÉ SIENDO USADA EN UN ARCHIVO PLANO PENDIENTE (NO GENERADO)
    IF EXISTS (SELECT 1 FROM   tab_det_archivo_plano AS a, tab_enc_archivo_plano AS b 
               WHERE  a.id_archivo_plano = b.id_archivo_plano
               AND    a.id_proveedor  = wid_proveedor
               AND    a.cta_proveedor = wcta_proveedor
               AND    b.ind_generado = FALSE) THEN
        RAISE EXCEPTION 'La cuenta % del proveedor % está siendo usada en un archivo plano pendiente y no puede ser borrada.', wcta_proveedor, wid_proveedor;
    END IF;

-- SI TODO VA BIEN, SE BORRA LÓGICAMENTE EN tab_bancoxprov
    UPDATE tab_bancoxprov
    SET    ind_borrado   = TRUE
    WHERE  id_proveedor  = wid_proveedor AND cta_proveedor = wcta_proveedor;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE LÓGICO DE ENCABEZADO DE CRONOGRAMA DE PAGOS
-- NOTA: Solo se permite borrar un cronograma "vacío", es decir, que no tenga
--       detalle (tab_det_cronopagos) ni cuotas en archivos planos (tab_det_archivo_plano).
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_enc_cronopagos (wid_cronograma     tab_enc_cronopagos.id_cronograma%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

    IF wid_cronograma IS NULL THEN
        RAISE EXCEPTION 'El ID del cronograma no puede ser nulo.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tab_enc_cronopagos WHERE id_cronograma = wid_cronograma AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El cronograma % no existe o ya se encuentra inactivo.', wid_cronograma;
    END IF;

    IF EXISTS (SELECT 1 FROM tab_det_cronopagos WHERE id_cronograma = wid_cronograma) THEN
        RAISE EXCEPTION 'El cronograma % tiene detalle asociado y no puede ser borrado.', wid_cronograma;
    END IF;

-- VALIDAR QUE NO TENGA LÍNEAS EN ARCHIVOS PLANOS (ahora id_cronograma está en el detalle)
    IF EXISTS (SELECT 1 FROM tab_det_archivo_plano WHERE id_cronograma = wid_cronograma) THEN
        RAISE EXCEPTION 'El cronograma % tiene cuotas en archivos planos y no puede ser borrado.', wid_cronograma;
    END IF;

    UPDATE tab_enc_cronopagos
    SET    ind_borrado    = TRUE
    WHERE  id_cronograma  = wid_cronograma;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE FÍSICO DE UNA LÍNEA DE DETALLE DE CRONOGRAMA DE PAGOS
-- NOTA: tab_det_cronopagos NO tiene ind_borrado, por lo que el borrado es FÍSICO (DELETE).
--       Solo se permite borrar detalle de un cronograma ACTIVO, que esté PENDIENTE (no pagado)
--       y que no tenga archivos planos GENERADOS. La cuota a borrar tampoco puede estar en
--       ningún archivo plano. total_a_pagar lo recalcula trg_calcular_total_cronograma.
--
--       REGLA ADICIONAL: un cronograma debe conservar SIEMPRE al menos una cuota. Por eso
--       no se permite eliminar la última línea de detalle (si tiene 2 puedes borrar 1, pero
--       no las 2). Para dejar el cronograma sin detalle, se debe eliminar el cronograma completo.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_det_cronopagos (wid_cronograma  tab_det_cronopagos.id_cronograma%TYPE,
                                                      wid_factura     tab_det_cronopagos.id_factura%TYPE,
                                                      wid_cuota       tab_det_cronopagos.id_cuota%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

    IF wid_cronograma IS NULL OR wid_factura IS NULL OR wid_cuota IS NULL THEN
        RAISE EXCEPTION 'El ID del cronograma, la factura y la cuota no pueden ser nulos.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tab_enc_cronopagos WHERE id_cronograma = wid_cronograma AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El cronograma % no existe o se encuentra inactivo.', wid_cronograma;
    END IF;

    IF EXISTS (SELECT 1 FROM tab_enc_cronopagos WHERE id_cronograma = wid_cronograma AND ind_estado = TRUE) THEN
        RAISE EXCEPTION 'El cronograma % ya se encuentra pagado y su detalle no puede ser modificado.', wid_cronograma;
    END IF;

-- VALIDAR QUE EL CRONOGRAMA NO TENGA CUOTAS EN ARCHIVOS PLANOS YA GENERADOS
    IF EXISTS (SELECT 1
                 FROM tab_det_archivo_plano d
                 JOIN tab_enc_archivo_plano e ON e.id_archivo_plano = d.id_archivo_plano
                WHERE d.id_cronograma = wid_cronograma
                  AND e.ind_generado  = TRUE) THEN
        RAISE EXCEPTION 'El cronograma % tiene archivos planos generados y su detalle no puede ser modificado.', wid_cronograma;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tab_det_cronopagos WHERE id_cronograma = wid_cronograma AND id_factura = wid_factura AND id_cuota = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % no existe en el detalle del cronograma %.', wid_cuota, wid_factura, wid_cronograma;
    END IF;

-- VALIDAR QUE ESA CUOTA NO ESTÉ EN NINGÚN ARCHIVO PLANO (aunque no esté generado)
    IF EXISTS (SELECT 1 FROM tab_det_archivo_plano
                WHERE id_cronograma = wid_cronograma
                  AND id_factura    = wid_factura
                  AND id_cuota      = wid_cuota) THEN
        RAISE EXCEPTION 'La cuota % de la factura % está en un archivo plano. Quítela del archivo antes de sacarla del cronograma.', wid_cuota, wid_factura;
    END IF;

    IF (SELECT COUNT(id_factura) FROM tab_det_cronopagos WHERE id_cronograma = wid_cronograma) <= 1 THEN
        RAISE EXCEPTION 'No se puede eliminar la última cuota del cronograma %. Un cronograma debe conservar al menos una cuota; si desea dejarlo vacío, elimine el cronograma completo.', wid_cronograma;
    END IF;

-- SE BORRA LA LÍNEA (trg_calcular_total_cronograma recalcula total_a_pagar)
    DELETE FROM tab_det_cronopagos
    WHERE  id_cronograma = wid_cronograma
    AND    id_factura    = wid_factura
    AND    id_cuota      = wid_cuota;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE LÓGICO DE TIPOS DE PAGO
-- NOTA: Es lógico para no romper los archivos planos que ya lo usan. No se permite si hay
--       archivos planos sin generar (ind_generado = FALSE) con este tipo de pago.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_tipos_pago (wid_tipo_pago     tab_tipos_pago.id_tipo_pago%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID NO SEA NULO
    IF wid_tipo_pago IS NULL THEN
        RAISE EXCEPTION 'El ID del tipo de pago no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL TIPO DE PAGO EXISTA Y NO ESTÉ YA BORRADO
    IF NOT EXISTS (SELECT 1 FROM tab_tipos_pago
                    WHERE id_tipo_pago = wid_tipo_pago AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El tipo de pago % no existe o ya se encuentra inactivo.', wid_tipo_pago;
    END IF;

-- VALIDAR QUE NO LO USE UN ARCHIVO PLANO PENDIENTE DE GENERAR
    IF EXISTS (SELECT 1 FROM tab_enc_archivo_plano
                WHERE id_tipo_pago = wid_tipo_pago AND ind_generado = FALSE) THEN
        RAISE EXCEPTION 'No se puede inactivar: hay archivos planos sin generar con el tipo de pago %.', wid_tipo_pago;
    END IF;

-- SI TODO VA BIEN, SE BORRA LÓGICAMENTE
    UPDATE tab_tipos_pago
    SET    ind_borrado  = TRUE
    WHERE  id_tipo_pago = wid_tipo_pago;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE LÓGICO DE CÓDIGOS DE RESPUESTA DEL BANCO
-- NOTA: Es lógico para no romper los pagos que ya usan el código.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_codigos_respuesta_banco (wid_codigo      tab_codigos_respuesta_banco.id_codigo%TYPE,
                                                               wid_banco       tab_codigos_respuesta_banco.id_banco%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE LOS CAMPOS NO SEAN NULOS
    IF wid_codigo IS NULL OR wid_banco IS NULL THEN
        RAISE EXCEPTION 'El código de respuesta y el banco no pueden ser nulos.';
    END IF;

-- VALIDAR QUE EL CÓDIGO EXISTA Y NO ESTÉ YA BORRADO
    IF NOT EXISTS (SELECT 1 FROM tab_codigos_respuesta_banco
                    WHERE id_codigo = wid_codigo AND id_banco = wid_banco AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El código % del banco % no existe o ya se encuentra inactivo.', wid_codigo, wid_banco;
    END IF;

-- SI TODO VA BIEN, SE BORRA LÓGICAMENTE
    UPDATE tab_codigos_respuesta_banco
    SET    ind_borrado = TRUE
    WHERE  id_codigo   = wid_codigo
      AND  id_banco    = wid_banco;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN DE DELETE LÓGICO DE BANCOS
-- NOTA: Esta función cambia ind_borrado de FALSE a TRUE (borrado lógico). No se permite
--       borrar un banco que esté siendo usado en cuentas activas de la empresa o de
--       proveedores.
--------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_delete_bancos (wid_banco     tab_bancos.id_banco%TYPE) RETURNS BOOLEAN AS
$BODY$
BEGIN

-- VALIDAR QUE EL ID DEL BANCO NO SEA NULO
    IF wid_banco IS NULL THEN
        RAISE EXCEPTION 'El ID del banco no puede ser nulo.';
    END IF;

-- VALIDAR QUE EL BANCO EXISTA Y NO ESTÉ YA BORRADO
    IF NOT EXISTS (SELECT 1 FROM tab_bancos WHERE id_banco = wid_banco AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El banco % no existe o ya se encuentra borrado.', wid_banco;
    END IF;

-- VALIDAR QUE EL BANCO NO ESTÉ SIENDO USADO EN CUENTAS ACTIVAS DE LA EMPRESA
    IF EXISTS (SELECT 1 FROM tab_ctas_empresa WHERE id_banco = wid_banco AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El banco % está asociado a cuentas activas de la empresa y no puede ser borrado.', wid_banco;
    END IF;

-- VALIDAR QUE EL BANCO NO ESTÉ SIENDO USADO EN CUENTAS ACTIVAS DE PROVEEDORES
    IF EXISTS (SELECT 1 FROM tab_bancoxprov WHERE id_banco = wid_banco AND ind_borrado = FALSE) THEN
        RAISE EXCEPTION 'El banco % está asociado a cuentas activas de proveedores y no puede ser borrado.', wid_banco;
    END IF;

-- SI TODO VA BIEN, SE BORRA LÓGICAMENTE EN tab_bancos
    UPDATE tab_bancos
    SET    ind_borrado = TRUE
    WHERE  id_banco    = wid_banco;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: %', public.fun_mensaje_error(SQLSTATE, SQLERRM);
END;
$BODY$
LANGUAGE PLPGSQL;
