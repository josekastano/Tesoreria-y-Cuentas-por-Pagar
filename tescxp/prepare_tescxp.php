<?php
/**
 * CENTRAL DE INSTRUCCIONES PREPARADAS - Módulo Tesorería y CxP
 * Versión: 3.1 — Alineada a script_BD_tesore_cxp.sql (modelo con
 *                tab_codigos_respuesta_banco y estado_pago numérico),
 *                fun_inserts / fun_updates / fun_deletes_tescxp.sql y
 *                triggers_tescxp.sql
 *
 * Orden de los bloques: igual al orden de creación de tablas en el script SQL.
 *
 *   1.  tab_pmtros_tescxp (+ tab_pmtros_grales, solo lectura)   (Tabla 1)
 *   2.  tab_festivos                                            (Tabla 2)
 *   3.  tab_enc_caja_menor / tab_det_caja_menor                 (Tablas 3 y 4)
 *   4.  tab_ctas_empresa                                        (Tabla 5)
 *   5.  tab_bancoxprov                                          (Tabla 6)
 *   6.  tab_cuentasxpagar / tab_cuotasxfactura                  (Tablas 7 y 8)
 *   7.  tab_enc_cronopagos / tab_det_cronopagos                 (Tablas 9 y 10)
 *   8.  tab_tipos_pago                                          (Tabla 11)
 *   9.  tab_enc_archivo_plano / tab_det_archivo_plano           (Tablas 12 y 13)
 *  10.  tab_codigos_respuesta_banco                             (Tabla 14)
 *  11.  tab_pagos_cxp                                           (Tabla 15)
 *  12.  tab_bancos  (catálogo compartido con otros módulos)
 *
 * ---------------------------------------------------------------------------
 * CONVENCIÓN DE ESTADOS DE PAGO (tab_pagos_cxp.estado_pago)
 * ---------------------------------------------------------------------------
 *     1 = PENDIENTE     2 = APROBADO     3 = RECHAZADO
 *  Las consultas devuelven además nom_estado_pago con el texto.
 *
 * ---------------------------------------------------------------------------
 * MARCAS EN LOS COMENTARIOS
 * ---------------------------------------------------------------------------
 *  >>> NUEVO              Consulta que no existía y que el módulo necesita.
 *  >>> CAMBIA             Diferencia respecto a la versión anterior.
 *
 * ---------------------------------------------------------------------------
 * QUÉ SE QUITÓ
 * ---------------------------------------------------------------------------
 *  - $del_pmtros_tescxp           fun_delete_pmtros_tescxp no existe.
 *  - $recalc_saldo_factura        Lo hace trg_actualizar_saldo_factura (9.2).
 *  - $list_cuotas_pagables        Todo pago sale de un archivo plano.
 *  - $get_cronograma_de_cuota     tab_pagos_cxp ya guarda id_cronograma.
 *  - $mark_cuota_pagada y
 *    $cerrar_cronograma_si_pagado Ahora los hacen fun_insert_pagos_cxp y
 *                                 fun_update_pagos_cxp al aprobar, en la misma
 *                                 operación (ya no hace falta transacción en PHP).
 *  - Todo lo de tab_motivos_rechazo y referencia_bancaria.
 *
 * ---------------------------------------------------------------------------
 * CAMBIOS EN script_BD_tesore_cxp.sql (versión adjunta)
 * ---------------------------------------------------------------------------
 *  - tab_pagos_cxp: la FK a códigos ahora es (id_codigo, id_banco), igual que
 *    la PK de tab_codigos_respuesta_banco. Con la FK de una sola columna la
 *    tabla no se creaba.
 *  - uq_pago_aprobado_cuota: WHERE estado_pago = 2 (comparaba con 'APROBADO'
 *    y no compilaba).
 *  - tab_det_archivo_plano: sin UNIQUE (id_factura, id_cuota), para poder
 *    reintentar cuotas rechazadas; en su lugar un índice normal.
 *  - id_codigo e id_banco son NOT NULL en tab_pagos_cxp: el pago se registra
 *    cuando llega la respuesta del banco, con su código.
 *
 * ---------------------------------------------------------------------------
 * ORDEN PARA MONTAR LA BD
 * ---------------------------------------------------------------------------
 *  1) script_BD_tesore_cxp.sql
 *  2) triggers_tescxp.sql
 *  3) fun_inserts_tescxp.sql
 *  4) fun_updates_tescxp.sql
 *  5) fun_deletes_tescxp.sql
 *  Cada archivo de funciones empieza borrando las versiones viejas que
 *  cambiaron de parámetros (archivo plano, pagos) o que ya no existen
 *  (motivos de rechazo).

 *  PENDIENTE: fun_update_enc_archivo_plano deja cambiar id_banco sin cambiar
 *  la cuenta, y entonces el banco ya no coincide con cta_empresa. Conviene que
 *  solo cambie el nombre.
 * ---------------------------------------------------------------------------
 *  REINTENTO DE PAGOS RECHAZADOS:
 *  Una cuota puede ir a un archivo plano nuevo solo si todas sus líneas
 *  anteriores tienen un pago RECHAZADO (3). Lo valida
 *  fun_insert_det_archivo_plano y lo refleja $list_cuotas_de_cronograma.
 * ---------------------------------------------------------------------------
 */

require_once('config.php');

try {
    $pdo = getDBConnection();

    // =========================================================================
    // 1. TAB_PMTROS_TESCXP (+ TAB_PMTROS_GRALES, solo lectura)       (Tabla 1)
    // =========================================================================

    // ---- PARÁMETROS GENERALES DE LA EMPRESA (solo lectura) ----
    $list_pmtros_grales = $pdo->prepare(
        "SELECT  id_empresa
           FROM  tab_pmtros_grales
          LIMIT  1"
    );

    // ---- PARÁMETROS DE TESORERÍA Y CXP (caso mono-empresa) ----
    // fec_diapago1..3 son días de la semana (1 = lunes ... 6 = sábado).
    // trg_validar_fecha_cronograma usa este mismo registro.
    $list_pmtros_tescxp = $pdo->prepare(
        "SELECT  id_empresa,
                 fec_diapago1,
                 fec_diapago2,
                 fec_diapago3,
                 val_min_reembolso
           FROM  tab_pmtros_tescxp
          WHERE  ind_borrado = FALSE
          LIMIT  1"
    );

    // ---- PARÁMETROS DE UNA EMPRESA ESPECÍFICA ----
    $get_pmtros_tescxp = $pdo->prepare(
        "SELECT  id_empresa,
                 fec_diapago1,
                 fec_diapago2,
                 fec_diapago3,
                 val_min_reembolso
           FROM  tab_pmtros_tescxp
          WHERE  id_empresa  = :wid_empresa
            AND  ind_borrado = FALSE"
    );

    // ---- INSERT — fun_insert_pmtros_tescxp (5 params) ----
    $ins_pmtros_tescxp = $pdo->prepare(
        "SELECT fun_insert_pmtros_tescxp(
            :wid_empresa,
            :wfec_diapago1,
            :wfec_diapago2,
            :wfec_diapago3,
            :wval_min_reembolso
        )"
    );

    // ---- UPDATE — fun_update_pmtros_tescxp (5 params) ----
    $upd_pmtros_tescxp = $pdo->prepare(
        "SELECT fun_update_pmtros_tescxp(
            :wid_empresa,
            :wfec_diapago1,
            :wfec_diapago2,
            :wfec_diapago3,
            :wval_min_reembolso
        )"
    );

    // =========================================================================
    // 2. TAB_FESTIVOS                                                (Tabla 2)
    // =========================================================================

    // ---- LISTADO PRINCIPAL ----
    $list_festivos = $pdo->prepare(
        "SELECT  id_festivo,
                 fecha,
                 nom_festivo
           FROM  tab_festivos
          WHERE  ind_borrado = FALSE
          ORDER BY fecha"
    );

    // ---- UN FESTIVO (formulario de edición) ----
    $get_festivo = $pdo->prepare(
        "SELECT  id_festivo,
                 fecha,
                 nom_festivo
           FROM  tab_festivos
          WHERE  id_festivo  = :wid_festivo
            AND  ind_borrado = FALSE"
    );

    // ---- VALIDACIÓN — ¿YA HAY UN FESTIVO ACTIVO EN ESA FECHA? ----
    // >>> NUEVO. fun_update_festivos valida la fecha repetida, pero
    //     fun_insert_festivos no; esto evita crear dos festivos el mismo día.
    $check_festivo_fecha = $pdo->prepare(
        "SELECT  EXISTS (
                    SELECT 1
                      FROM tab_festivos
                     WHERE fecha       = :wfecha
                       AND ind_borrado = FALSE
                 ) AS existe"
    );

    // ---- INSERT — fun_insert_festivos (2 params) ----
    // fecha, nom_festivo (id_festivo se autogenera)
    $ins_festivo = $pdo->prepare(
        "SELECT fun_insert_festivos(
            :wfecha,
            :wnom_festivo
        )"
    );

    // ---- UPDATE — fun_update_festivos (3 params) ----
    $upd_festivo = $pdo->prepare(
        "SELECT fun_update_festivos(
            :wid_festivo,
            :wfecha,
            :wnom_festivo
        )"
    );

    // ---- DELETE — fun_delete_festivos (1 param) — borrado lógico ----
    $del_festivo = $pdo->prepare(
        "SELECT fun_delete_festivos(:wid_festivo)"
    );

    // =========================================================================
    // 3. TAB_ENC_CAJA_MENOR / TAB_DET_CAJA_MENOR                (Tablas 3 y 4)
    // =========================================================================

    // ---- LISTADO DE CAJAS MENORES ----
    $list_enc_caja_menor = $pdo->prepare(
        "SELECT  id_caja_menor,
                 nom_caja_menor,
                 monto_asignado,
                 monto_disponible,
                 fecha_apertura,
                 fecha_cierre,
                 ind_estado_caja_m
           FROM  tab_enc_caja_menor
          WHERE  ind_borrado = FALSE
          ORDER BY fecha_apertura DESC, id_caja_menor DESC"
    );

    // ---- CAJAS ABIERTAS (para selects) ----
    $list_cajas_activas = $pdo->prepare(
        "SELECT  id_caja_menor,
                 nom_caja_menor,
                 monto_disponible
           FROM  tab_enc_caja_menor
          WHERE  ind_borrado       = FALSE
            AND  ind_estado_caja_m = TRUE
          ORDER BY nom_caja_menor"
    );

    // ---- UNA CAJA MENOR ----
    $get_enc_caja_menor = $pdo->prepare(
        "SELECT  id_caja_menor,
                 nom_caja_menor,
                 monto_asignado,
                 monto_disponible,
                 fecha_apertura,
                 fecha_cierre,
                 ind_estado_caja_m
           FROM  tab_enc_caja_menor
          WHERE  id_caja_menor = :wid_caja_menor
            AND  ind_borrado   = FALSE"
    );

    // ---- MOVIMIENTOS DE UNA CAJA ----
    $list_det_caja_menor = $pdo->prepare(
        "SELECT  id_caja_menor,
                 id_movimiento,
                 concepto,
                 val_movimiento,
                 fecha_movimiento,
                 ind_estado
           FROM  tab_det_caja_menor
          WHERE  id_caja_menor = :wid_caja_menor
          ORDER BY id_movimiento DESC"
    );

    // ---- UN MOVIMIENTO (PK compuesta) ----
    $get_det_caja_menor = $pdo->prepare(
        "SELECT  id_caja_menor,
                 id_movimiento,
                 concepto,
                 val_movimiento,
                 fecha_movimiento,
                 ind_estado
           FROM  tab_det_caja_menor
          WHERE  id_caja_menor = :wid_caja_menor
            AND  id_movimiento = :wid_movimiento"
    );

    // ---- MOVIMIENTOS POR ESTADO (1 = Pendiente, 2 = Aprobado, 3 = Reembolsado) ----
    $list_mov_caja_por_estado = $pdo->prepare(
        "SELECT  d.id_caja_menor,
                 e.nom_caja_menor,
                 d.id_movimiento,
                 d.concepto,
                 d.val_movimiento,
                 d.fecha_movimiento,
                 d.ind_estado
           FROM  tab_det_caja_menor  d
           JOIN  tab_enc_caja_menor  e ON e.id_caja_menor = d.id_caja_menor
          WHERE  e.ind_borrado = FALSE
            AND  d.ind_estado  = :wind_estado
          ORDER BY d.fecha_movimiento DESC, d.id_movimiento DESC"
    );

    // ---- TOTALES POR ESTADO DE UNA CAJA ----
    // fun_delete_enc_caja_menor falla si quedan movimientos en estado 1 o 2.
    $sum_det_caja_menor = $pdo->prepare(
        "SELECT  ind_estado,
                 COUNT(*)              AS cant_movimientos,
                 SUM(val_movimiento)   AS total_movimientos
           FROM  tab_det_caja_menor
          WHERE  id_caja_menor = :wid_caja_menor
          GROUP BY ind_estado
          ORDER BY ind_estado"
    );

    // ---- ¿LA CAJA YA ALCANZÓ EL MÍNIMO PARA PEDIR REEMBOLSO? ----
    // Compara lo aprobado sin reembolsar (estado 2) contra val_min_reembolso.
    // (El trigger 2.2 tiene esto como PENDIENTE; mientras tanto lo valida la app.)
    $check_min_reembolso = $pdo->prepare(
        "SELECT  COALESCE(SUM(d.val_movimiento), 0)      AS total_aprobado,
                 p.val_min_reembolso,
                 COALESCE(SUM(d.val_movimiento), 0) >= p.val_min_reembolso
                                                         AS alcanza_minimo
           FROM  tab_pmtros_tescxp p
           LEFT JOIN tab_det_caja_menor d
                  ON d.id_caja_menor = :wid_caja_menor
                 AND d.ind_estado    = 2
          WHERE  p.ind_borrado = FALSE
          GROUP BY p.val_min_reembolso"
    );

    // ---- INSERT — fun_insert_enc_caja_menor (2 params) ----
    // nom_caja_menor, monto_asignado
    // (trg_monto_disponible_caja_menor iguala monto_disponible = monto_asignado)
    $ins_enc_caja_menor = $pdo->prepare(
        "SELECT fun_insert_enc_caja_menor(
            :wnom_caja_menor,
            :wmonto_asignado
        )"
    );

    // ---- UPDATE — fun_update_enc_caja_menor (2 params) — solo renombra ----
    $upd_enc_caja_menor = $pdo->prepare(
        "SELECT fun_update_enc_caja_menor(
            :wid_caja_menor,
            :wnom_caja_menor
        )"
    );

    // ---- INSERT — fun_insert_det_caja_menor (4 params) ----
    // id_caja_menor, concepto, val_movimiento, fecha_movimiento
    // >>> CAMBIA (comentario): el movimiento entra en Pendiente y NO descuenta
    //     nada al insertarse. trg_actualizar_disponible_caja_menor descuenta
    //     al pasar a Aprobado (1->2) y repone al pasar a Reembolsado (2->3).
    //     Además trg_fecha_movimiento_caja_menor fuerza fecha_movimiento =
    //     CURRENT_DATE, así que el valor que se mande aquí se ignora.
    $ins_det_caja_menor = $pdo->prepare(
        "SELECT fun_insert_det_caja_menor(
            :wid_caja_menor,
            :wconcepto,
            :wval_movimiento,
            :wfecha_movimiento
        )"
    );

    // ---- UPDATE — fun_update_det_caja_menor (3 params) ----
    // id_caja_menor, id_movimiento, ind_estado (solo avanza: 1 -> 2 -> 3)
    $upd_det_caja_menor = $pdo->prepare(
        "SELECT fun_update_det_caja_menor(
            :wid_caja_menor,
            :wid_movimiento,
            :wind_estado
        )"
    );

    // ---- CIERRE DE CAJA — fun_delete_enc_caja_menor (1 param) ----
    // Falla si quedan movimientos en estado 1 o 2.
    $del_enc_caja_menor = $pdo->prepare(
        "SELECT fun_delete_enc_caja_menor(:wid_caja_menor)"
    );

    // ---- BORRADO LÓGICO DE UNA CAJA YA CERRADA ----
    // No hay función para esto (fun_delete_enc_caja_menor solo cierra).
    // El WHERE impide borrar una caja abierta o con movimientos sin reembolsar.
    $borrar_enc_caja_menor = $pdo->prepare(
        "UPDATE tab_enc_caja_menor e
            SET ind_borrado = TRUE
          WHERE e.id_caja_menor     = :wid_caja_menor
            AND e.ind_borrado       = FALSE
            AND e.ind_estado_caja_m = FALSE
            AND NOT EXISTS (
                    SELECT 1
                      FROM tab_det_caja_menor d
                     WHERE d.id_caja_menor = e.id_caja_menor
                       AND d.ind_estado   IN (1, 2)
                 )"
    );

    // =========================================================================
    // 4. TAB_CTAS_EMPRESA                                            (Tabla 5)
    // =========================================================================

    // ---- BANCOS ACTIVOS (catálogo para selects) ----
    $list_bancos = $pdo->prepare(
        "SELECT  id_banco, nom_banco
           FROM  tab_bancos
          WHERE  ind_borrado = FALSE
            AND  ind_estado  = TRUE
          ORDER BY nom_banco"
    );

    // ---- LISTADO DE CUENTAS DE LA EMPRESA ----
    // También es el select de cuenta de origen del archivo plano.
    // >>> CAMBIA: trae también nom_empresa (tab_pmtros_grales), que el
    //     archivo plano copia en su encabezado.
    $list_ctas_empresa = $pdo->prepare(
        "SELECT  c.id_empresa,
                 g.nom_empresa,
                 c.cta_empresa,
                 c.id_banco,
                 b.nom_banco,
                 c.ind_tipocuenta
           FROM  tab_ctas_empresa  c
           JOIN  tab_bancos        b ON b.id_banco   = c.id_banco
           JOIN  tab_pmtros_grales g ON g.id_empresa = c.id_empresa
          WHERE  c.ind_borrado = FALSE
          ORDER BY b.nom_banco, c.cta_empresa"
    );

    // ---- UNA CUENTA DE LA EMPRESA ----
    // Al armar el encabezado del archivo plano, de aquí salen id_banco e
    // ind_tipocuenta de la cuenta elegida.
    $get_cta_empresa = $pdo->prepare(
        "SELECT  c.id_empresa,
                 c.cta_empresa,
                 c.id_banco,
                 b.nom_banco,
                 c.ind_tipocuenta
           FROM  tab_ctas_empresa  c
           JOIN  tab_bancos        b ON b.id_banco = c.id_banco
          WHERE  c.id_empresa  = :wid_empresa
            AND  c.cta_empresa = :wcta_empresa
            AND  c.ind_borrado = FALSE"
    );

    // ---- CUENTAS DE LA EMPRESA EN UN BANCO ----
    $list_ctas_empresa_banco = $pdo->prepare(
        "SELECT  c.id_empresa,
                 c.cta_empresa,
                 c.ind_tipocuenta
           FROM  tab_ctas_empresa  c
          WHERE  c.ind_borrado = FALSE
            AND  c.id_banco    = :wid_banco
          ORDER BY c.cta_empresa"
    );

    // ---- INSERT — fun_insert_ctas_empresa (4 params) ----
    $ins_cta_empresa = $pdo->prepare(
        "SELECT fun_insert_ctas_empresa(
            :wid_empresa,
            :wcta_empresa,
            :wid_banco,
            :wind_tipocuenta
        )"
    );

    // ---- UPDATE — fun_update_ctas_empresa (4 params) ----
    $upd_cta_empresa = $pdo->prepare(
        "SELECT fun_update_ctas_empresa(
            :wid_empresa,
            :wcta_empresa,
            :wid_banco,
            :wind_tipocuenta
        )"
    );

    // ---- DELETE — fun_delete_ctas_empresa (2 params) — borrado lógico ----
    // (en fun_deletes_tescxp.sql)
    $del_cta_empresa = $pdo->prepare(
        "SELECT fun_delete_ctas_empresa(
            :wid_empresa,
            :wcta_empresa
        )"
    );

    // =========================================================================
    // 5. TAB_BANCOXPROV                                              (Tabla 6)
    // =========================================================================

    // ---- PROVEEDORES (catálogo para selects) ----
    $list_proveedores_select = $pdo->prepare(
        "SELECT  p.id_proveedor,
                 t.nom_tercero
           FROM  tab_proveedores p
           JOIN  tab_terceros    t ON t.id_tercero = p.id_proveedor
          WHERE  p.ind_borrado = FALSE
            AND  t.ind_borrado = FALSE
          ORDER BY t.nom_tercero"
    );

    // ---- LISTADO DE CUENTAS DE PROVEEDORES ----
    $list_bancoxprov = $pdo->prepare(
        "SELECT  bp.id_proveedor,
                 t.nom_tercero,
                 bp.cta_proveedor,
                 bp.id_banco,
                 b.nom_banco,
                 bp.ind_tipocuenta
           FROM  tab_bancoxprov  bp
           JOIN  tab_terceros    t ON t.id_tercero = bp.id_proveedor
           JOIN  tab_bancos      b ON b.id_banco   = bp.id_banco
          WHERE  bp.ind_borrado = FALSE
          ORDER BY t.nom_tercero, bp.cta_proveedor"
    );

    // ---- UNA CUENTA DE PROVEEDOR ----
    $get_bancoxprov = $pdo->prepare(
        "SELECT  bp.id_proveedor,
                 t.nom_tercero,
                 bp.cta_proveedor,
                 bp.id_banco,
                 b.nom_banco,
                 bp.ind_tipocuenta
           FROM  tab_bancoxprov  bp
           JOIN  tab_terceros    t ON t.id_tercero = bp.id_proveedor
           JOIN  tab_bancos      b ON b.id_banco   = bp.id_banco
          WHERE  bp.id_proveedor  = :wid_proveedor
            AND  bp.cta_proveedor = :wcta_proveedor
            AND  bp.ind_borrado   = FALSE"
    );

    // ---- CUENTAS ACTIVAS DE UN PROVEEDOR (en bancos activos) ----
    $list_ctas_de_proveedor = $pdo->prepare(
        "SELECT  bp.id_proveedor,
                 bp.cta_proveedor,
                 bp.id_banco,
                 b.nom_banco,
                 bp.ind_tipocuenta
           FROM  tab_bancoxprov  bp
           JOIN  tab_bancos      b ON b.id_banco = bp.id_banco
          WHERE  bp.ind_borrado   = FALSE
            AND  b.ind_borrado    = FALSE
            AND  b.ind_estado     = TRUE
            AND  bp.id_proveedor  = :wid_proveedor
          ORDER BY b.nom_banco, bp.cta_proveedor"
    );

    // ---- INSERT — fun_insert_bancoxprov (4 params) ----
    $ins_bancoxprov = $pdo->prepare(
        "SELECT fun_insert_bancoxprov(
            :wid_proveedor,
            :wcta_proveedor,
            :wid_banco,
            :wind_tipocuenta
        )"
    );

    // ---- UPDATE — fun_update_bancoxprov (4 params) ----
    $upd_bancoxprov = $pdo->prepare(
        "SELECT fun_update_bancoxprov(
            :wid_proveedor,
            :wcta_proveedor,
            :wid_banco,
            :wind_tipocuenta
        )"
    );

    // ---- DELETE — fun_delete_bancoxprov (2 params) — borrado lógico ----
    // Siempre lógico: tab_det_archivo_plano tiene FK a (id_proveedor, cta_proveedor).
    $del_bancoxprov = $pdo->prepare(
        "SELECT fun_delete_bancoxprov(
            :wid_proveedor,
            :wcta_proveedor
        )"
    );

    // =========================================================================
    // 6. TAB_CUENTASXPAGAR / TAB_CUOTASXFACTURA                 (Tablas 7 y 8)
    // =========================================================================

    // ---- PROVEEDORES CON DÍAS DE PAGO ----
    // (fec_vencimiento = fec_emision + ind_dias_pago)
    $list_proveedores_dias_pago = $pdo->prepare(
        "SELECT  p.id_proveedor,
                 t.nom_tercero,
                 p.ind_dias_pago
           FROM  tab_proveedores p
           JOIN  tab_terceros    t ON t.id_tercero = p.id_proveedor
          WHERE  p.ind_borrado = FALSE
            AND  t.ind_borrado = FALSE
          ORDER BY t.nom_tercero"
    );

    // ---- ÓRDENES DE COMPRA FACTURABLES DE UN PROVEEDOR ----
    // >>> NUEVO. fun_insert_cuentasxpagar exige que la OC sea del mismo
    //     proveedor, esté aprobada (ind_estado = 1) y tenga saldo. Este select
    //     solo ofrece las que cumplen, con el saldo disponible para mostrarlo.
    $list_ordenes_facturables = $pdo->prepare(
        "SELECT  o.id_ordencompra,
                 o.val_total,
                 COALESCE(SUM(f.val_factura), 0)                AS val_facturado,
                 o.val_total - COALESCE(SUM(f.val_factura), 0)  AS saldo_disponible
           FROM  tab_enc_ordcomp   o
           LEFT JOIN tab_cuentasxpagar f ON f.id_ordencompra = o.id_ordencompra
          WHERE  o.id_proveedor = :wid_proveedor
            AND  o.ind_estado   = 1
          GROUP BY o.id_ordencompra, o.val_total
         HAVING  o.val_total - COALESCE(SUM(f.val_factura), 0) > 0
          ORDER BY o.id_ordencompra"
    );

    // ---- LISTADO DE FACTURAS ----
    $list_cuentasxpagar = $pdo->prepare(
        "SELECT  f.id_factura,
                 f.id_proveedor,
                 f.id_ordencompra,
                 t.nom_tercero,
                 f.fec_emision,
                 f.fec_vencimiento,
                 f.val_factura,
                 f.val_saldo,
                 f.num_cuotas,
                 f.ind_estado
           FROM  tab_cuentasxpagar f
           JOIN  tab_terceros      t ON t.id_tercero = f.id_proveedor
          ORDER BY f.fec_vencimiento"
    );

    // ---- UNA FACTURA ----
    $get_cuentasxpagar = $pdo->prepare(
        "SELECT  f.id_factura,
                 f.id_proveedor,
                 f.id_ordencompra,
                 t.nom_tercero,
                 f.fec_emision,
                 f.fec_vencimiento,
                 f.val_factura,
                 f.val_saldo,
                 f.num_cuotas,
                 f.ind_estado
           FROM  tab_cuentasxpagar f
           JOIN  tab_terceros      t ON t.id_tercero = f.id_proveedor
          WHERE  f.id_factura = :wid_factura"
    );

    // ---- VALIDACIÓN — ¿YA EXISTE ESA FACTURA? ----
    $check_factura_existe = $pdo->prepare(
        "SELECT  EXISTS (
                    SELECT 1
                      FROM tab_cuentasxpagar
                     WHERE id_factura = :wid_factura
                 ) AS existe"
    );

    // ---- FACTURAS DE UN PROVEEDOR ----
    $list_facturas_proveedor = $pdo->prepare(
        "SELECT  f.id_factura,
                 f.id_ordencompra,
                 f.fec_emision,
                 f.fec_vencimiento,
                 f.val_factura,
                 f.val_saldo,
                 f.num_cuotas,
                 f.ind_estado
           FROM  tab_cuentasxpagar f
          WHERE  f.id_proveedor = :wid_proveedor
          ORDER BY f.fec_vencimiento"
    );

    // ---- FACTURAS PENDIENTES (tablero) ----
    $list_facturas_pendientes = $pdo->prepare(
        "SELECT  f.id_factura,
                 f.id_proveedor,
                 t.nom_tercero,
                 f.fec_vencimiento,
                 f.val_factura,
                 f.val_saldo,
                 f.fec_vencimiento < CURRENT_DATE AS esta_vencida
           FROM  tab_cuentasxpagar f
           JOIN  tab_terceros      t ON t.id_tercero = f.id_proveedor
          WHERE  f.ind_estado = FALSE
          ORDER BY f.fec_vencimiento"
    );

    // ---- CUOTAS DE UNA FACTURA (las genera trg_generar_cuotas_factura) ----
    $list_cuotasxfactura = $pdo->prepare(
        "SELECT  id_factura,
                 id_cuota,
                 fec_vencimiento,
                 val_cuota,
                 ind_pagada
           FROM  tab_cuotasxfactura
          WHERE  id_factura = :wid_factura
          ORDER BY id_cuota"
    );

    // ---- INSERT — fun_insert_cuentasxpagar (7 params) ----
    // >>> CAMBIA (comentario): son 7 parámetros, no 6.
    // id_factura, id_proveedor, id_ordencompra (NULL si no hay OC),
    // fec_emision, fec_vencimiento, val_factura, num_cuotas
    // (val_saldo y las cuotas los ponen los triggers 3.1 y 4.1.
    //  La factura no se actualiza ni se borra.)
    // OJO: la tabla exige fec_vencimiento > fec_emision (estricto) aunque la
    // función deja pasar fechas iguales; validar en pantalla que sea mayor.
    $ins_cuentasxpagar = $pdo->prepare(
        "SELECT fun_insert_cuentasxpagar(
            :wid_factura,
            :wid_proveedor,
            :wid_ordencompra,
            :wfec_emision,
            :wfec_vencimiento,
            :wval_factura,
            :wnum_cuotas
        )"
    );

    // =========================================================================
    // 7. TAB_ENC_CRONOPAGOS / TAB_DET_CRONOPAGOS               (Tablas 9 y 10)
    // =========================================================================

    // ---- LISTADO DE CRONOGRAMAS ----
    $list_enc_cronopagos = $pdo->prepare(
        "SELECT  id_cronograma,
                 nom_cronograma,
                 fec_programacion,
                 total_a_pagar,
                 ind_estado
           FROM  tab_enc_cronopagos
          WHERE  ind_borrado = FALSE
          ORDER BY fec_programacion DESC, id_cronograma DESC"
    );

    // ---- UN CRONOGRAMA ----
    $get_enc_cronopagos = $pdo->prepare(
        "SELECT  id_cronograma,
                 nom_cronograma,
                 fec_programacion,
                 total_a_pagar,
                 ind_estado
           FROM  tab_enc_cronopagos
          WHERE  id_cronograma = :wid_cronograma
            AND  ind_borrado   = FALSE"
    );

    // ---- DETALLE DE UN CRONOGRAMA ----
    $list_det_cronopagos = $pdo->prepare(
        "SELECT  d.id_cronograma,
                 d.id_factura,
                 d.id_cuota,
                 d.val_a_pagar,
                 c.fec_vencimiento,
                 c.ind_pagada,
                 f.id_proveedor,
                 t.nom_tercero
           FROM  tab_det_cronopagos  d
           JOIN  tab_cuotasxfactura  c ON c.id_factura = d.id_factura AND c.id_cuota = d.id_cuota
           JOIN  tab_cuentasxpagar   f ON f.id_factura = d.id_factura
           JOIN  tab_terceros        t ON t.id_tercero = f.id_proveedor
          WHERE  d.id_cronograma = :wid_cronograma
          ORDER BY t.nom_tercero, d.id_factura, d.id_cuota"
    );

    // ---- CUOTAS DISPONIBLES PARA ARMAR UN CRONOGRAMA ----
    // Primera cuota pendiente de cada factura que no esté en ningún
    // cronograma (uq_cuota_programada es global, sin mirar ind_borrado).
    $list_cuotas_pendientes = $pdo->prepare(
        "SELECT  c.id_factura,
                 c.id_cuota,
                 c.fec_vencimiento,
                 c.val_cuota,
                 f.id_proveedor,
                 t.nom_tercero
           FROM  tab_cuotasxfactura  c
           JOIN  tab_cuentasxpagar   f ON f.id_factura = c.id_factura
           JOIN  tab_terceros        t ON t.id_tercero = f.id_proveedor
          WHERE  c.ind_pagada = FALSE
            AND  NOT EXISTS (
                    SELECT 1
                      FROM tab_cuotasxfactura c2
                     WHERE c2.id_factura = c.id_factura
                       AND c2.ind_pagada = FALSE
                       AND c2.id_cuota   < c.id_cuota
                 )
            AND  NOT EXISTS (
                    SELECT 1
                      FROM tab_det_cronopagos dc
                     WHERE dc.id_factura = c.id_factura
                       AND dc.id_cuota   = c.id_cuota
                 )
          ORDER BY c.fec_vencimiento"
    );

    // ---- VENCIMIENTO DE UNA CUOTA (validación en pantalla) ----
    $get_venc_cuota = $pdo->prepare(
        "SELECT  fec_vencimiento
           FROM  tab_cuotasxfactura
          WHERE  id_factura = :wid_factura
            AND  id_cuota   = :wid_cuota"
    );

    // ---- VENCIMIENTO MÁS LEJANO DE LAS CUOTAS DE UN CRONOGRAMA ----
    $get_max_venc_cronograma = $pdo->prepare(
        "SELECT  MAX(c.fec_vencimiento)
           FROM  tab_det_cronopagos  d
           JOIN  tab_cuotasxfactura  c ON c.id_factura = d.id_factura
                                      AND c.id_cuota   = d.id_cuota
          WHERE  d.id_cronograma = :wid_cronograma"
    );

    // ---- INSERT — fun_insert_enc_cronopagos (2 params) ----
    // nom_cronograma, fec_programacion
    // (trg_validar_fecha_cronograma rechaza días que no sean de pago y festivos)
    $ins_enc_cronopagos = $pdo->prepare(
        "SELECT fun_insert_enc_cronopagos(
            :wnom_cronograma,
            :wfec_programacion
        )"
    );

    // ---- INSERT — fun_insert_det_cronopagos (3 params) ----
    // id_cronograma, id_factura, id_cuota
    // (val_a_pagar lo pone trg_val_a_pagar_cronograma y total_a_pagar
    //  lo recalcula trg_calcular_total_cronograma)
    $ins_det_cronopagos = $pdo->prepare(
        "SELECT fun_insert_det_cronopagos(
            :wid_cronograma,
            :wid_factura,
            :wid_cuota
        )"
    );

    // ---- UPDATE — fun_update_enc_cronopagos (3 params) ----
    $upd_enc_cronopagos = $pdo->prepare(
        "SELECT fun_update_enc_cronopagos(
            :wid_cronograma,
            :wnom_cronograma,
            :wfec_programacion
        )"
    );

    // ---- DELETE — fun_delete_enc_cronopagos (1 param) — borrado lógico ----
    // Solo cronogramas vacíos. (en fun_deletes_tescxp.sql)
    $del_enc_cronopagos = $pdo->prepare(
        "SELECT fun_delete_enc_cronopagos(:wid_cronograma)"
    );

    // ---- DELETE — fun_delete_det_cronopagos (3 params) — borrado físico ----
    // No deja borrar la última cuota del cronograma ni una cuota que esté en
    // un archivo plano. (en fun_deletes_tescxp.sql)
    $del_det_cronopagos = $pdo->prepare(
        "SELECT fun_delete_det_cronopagos(
            :wid_cronograma,
            :wid_factura,
            :wid_cuota
        )"
    );

    // ---- CRONOGRAMAS PENDIENTES (para generar archivo plano) ----
    $list_cronogramas_pendientes = $pdo->prepare(
        "SELECT  id_cronograma,
                 nom_cronograma,
                 fec_programacion,
                 total_a_pagar
           FROM  tab_enc_cronopagos
          WHERE  ind_borrado = FALSE
            AND  ind_estado  = FALSE
          ORDER BY fec_programacion"
    );

    // ---- ¿EL CRONOGRAMA YA TIENE LÍNEAS EN ARCHIVOS PLANOS? ----
    // >>> CAMBIA: id_cronograma ya no está en el encabezado del archivo plano,
    //     ahora está en el detalle. Devuelve si tiene líneas y si alguna está
    //     en un archivo ya generado (que es lo que bloquea editar el detalle).
    $check_crono_con_archivo = $pdo->prepare(
        "SELECT  EXISTS (
                    SELECT 1
                      FROM tab_det_archivo_plano d
                     WHERE d.id_cronograma = :wid_cronograma
                 ) AS tiene_archivo,
                 EXISTS (
                    SELECT 1
                      FROM tab_det_archivo_plano d
                      JOIN tab_enc_archivo_plano e ON e.id_archivo_plano = d.id_archivo_plano
                     WHERE d.id_cronograma = :wid_cronograma2
                       AND e.ind_generado  = TRUE
                 ) AS tiene_archivo_generado"
    );
    // (PDO_PGSQL no permite repetir un placeholder: mandar el mismo valor en
    //  :wid_cronograma y :wid_cronograma2)

    // =========================================================================
    // 8. TAB_TIPOS_PAGO                                             (Tabla 11)
    // =========================================================================
    // >>> NUEVO bloque. Lo usan archivo_plano.php (select del encabezado) y
    //     tipos_pago.php (administración).
    //     Funciones: fun_insert_tipos_pago, fun_update_tipos_pago y
    //     fun_delete_tipos_pago (borrado lógico).

    // ---- ACTIVOS (combo del encabezado de archivo plano) ----

    $list_tipos_pago = $pdo->prepare(
        "SELECT  id_tipo_pago,
                 nom_tipo_pago
           FROM  tab_tipos_pago
          WHERE  ind_borrado = FALSE
          ORDER BY id_tipo_pago"
    );

    $get_tipo_pago = $pdo->prepare(
        "SELECT  id_tipo_pago,
                 nom_tipo_pago
           FROM  tab_tipos_pago
          WHERE  id_tipo_pago = :wid_tipo_pago
            AND  ind_borrado  = FALSE"
    );

    // ---- LISTADO DE ADMINISTRACIÓN (incluye inactivos, para reactivarlos) ----
    $list_tipos_pago_admin = $pdo->prepare(
        "SELECT  id_tipo_pago,
                 nom_tipo_pago,
                 ind_borrado
           FROM  tab_tipos_pago
          ORDER BY id_tipo_pago"
    );

    // ---- UN TIPO DE PAGO, ACTIVO O NO (para validar y para editar/reactivar) ----
    $get_tipo_pago_admin = $pdo->prepare(
        "SELECT  id_tipo_pago,
                 nom_tipo_pago,
                 ind_borrado
           FROM  tab_tipos_pago
          WHERE  id_tipo_pago = :wid_tipo_pago"
    );

    // ---- ¿NOMBRE REPETIDO EN OTRO TIPO DE PAGO? (para marcar el campo en el formulario) ----
    $check_nom_tipo_pago = $pdo->prepare(
        "SELECT  COUNT(*)
           FROM  tab_tipos_pago
          WHERE  UPPER(nom_tipo_pago) = UPPER(:wnom_tipo_pago)
            AND  id_tipo_pago        <> :wid_tipo_pago"
    );

    // ---- INSERT — fun_insert_tipos_pago (2 params) ----
    // (ind_borrado entra en FALSE por DEFAULT; el nombre se guarda en mayúsculas)
    $ins_tipo_pago = $pdo->prepare(
        "SELECT fun_insert_tipos_pago(
            :wid_tipo_pago,
            :wnom_tipo_pago
        )"
    );

    // ---- UPDATE — fun_update_tipos_pago (3 params) ----
    // id_tipo_pago (no cambia), nom_tipo_pago, ind_borrado
    // (ind_borrado = FALSE reactiva; para inactivar se usa $del_tipo_pago)
    $upd_tipo_pago = $pdo->prepare(
        "SELECT fun_update_tipos_pago(
            :wid_tipo_pago,
            :wnom_tipo_pago,
            :wind_borrado
        )"
    );

    // ---- DELETE — fun_delete_tipos_pago (1 param) — borrado lógico ----
    // No deja inactivar si hay archivos planos sin generar con ese tipo.
    $del_tipo_pago = $pdo->prepare(
        "SELECT fun_delete_tipos_pago(
            :wid_tipo_pago
        )"
    );

    // =========================================================================
    // 9. TAB_ENC_ARCHIVO_PLANO / TAB_DET_ARCHIVO_PLANO        (Tablas 12 y 13)
    // =========================================================================
    // >>> CAMBIA todo el bloque. Con el modelo nuevo:
    //     - El ENCABEZADO guarda la cuenta de origen (id_empresa, cta_empresa,
    //       id_banco, ind_tipocuenta), nom_empresa, fecha_aplicacion e
    //       id_tipo_pago. Ya no está atado a un cronograma.
    //     - El DETALLE guarda id_cronograma y una copia de los datos del
    //       beneficiario (id_tipo, nom_tercero, id_banco, ind_tipocuenta,
    //       cta_proveedor), para que el archivo conserve lo que se envió.
    //     - Un mismo archivo puede llevar cuotas de varios cronogramas.
    //     - Una cuota puede estar en varios archivos solo como reintento: cada
    //       archivo anterior debe tener su pago RECHAZADO.

    // ---- CUOTAS DE UN CRONOGRAMA DISPONIBLES PARA UN ARCHIVO PLANO ----
    // (una fila por cuota; las cuentas del proveedor se traen aparte)
    // id_tipo (NIT, CC...) sale de tab_terceros y se copia al detalle del archivo.
    // >>> CAMBIA: una cuota está disponible si nunca ha ido a un archivo, o
    //     si todos los archivos donde fue tienen su pago RECHAZADO (3) (reintento).
    //     Si está en un archivo sin respuesta, PENDIENTE o APROBADO, no sale.
    //     Es la misma regla que valida fun_insert_det_archivo_plano.
    $list_cuotas_de_cronograma = $pdo->prepare(
        "SELECT  d.id_cronograma,
                 d.id_factura,
                 d.id_cuota,
                 d.val_a_pagar,
                 f.id_proveedor,
                 t.id_tipo,
                 t.nom_tercero,
                 -- TRUE si la cuota ya estuvo en otro archivo y el banco la
                 -- rechazó (por el filtro de abajo, todas sus líneas previas
                 -- están rechazadas): es un reintento.
                 EXISTS (
                    SELECT 1
                      FROM tab_det_archivo_plano ap2
                     WHERE ap2.id_factura = d.id_factura
                       AND ap2.id_cuota   = d.id_cuota
                 ) AS es_reintento
           FROM  tab_det_cronopagos  d
           JOIN  tab_cuentasxpagar   f ON f.id_factura = d.id_factura
           JOIN  tab_terceros        t ON t.id_tercero = f.id_proveedor
           JOIN  tab_cuotasxfactura  c ON c.id_factura = d.id_factura
                                      AND c.id_cuota   = d.id_cuota
          WHERE  d.id_cronograma = :wid_cronograma
            AND  c.ind_pagada    = FALSE
            AND  NOT EXISTS (
                    SELECT 1
                      FROM tab_det_archivo_plano ap
                     WHERE ap.id_factura = d.id_factura
                       AND ap.id_cuota   = d.id_cuota
                       AND NOT EXISTS (
                               SELECT 1
                                 FROM tab_pagos_cxp p
                                WHERE p.id_archivo_plano = ap.id_archivo_plano
                                  AND p.id_cronograma    = ap.id_cronograma
                                  AND p.id_factura       = ap.id_factura
                                  AND p.id_cuota         = ap.id_cuota
                                  AND p.estado_pago      = 3
                           )
                 )
          ORDER BY t.nom_tercero, d.id_factura, d.id_cuota"
    );

    // ---- CUENTAS ACTIVAS DE LOS PROVEEDORES DE UN CRONOGRAMA ----
    // (se agrupa en PHP por id_proveedor para pintar un select por proveedor)
    $list_ctas_prov_de_cronograma = $pdo->prepare(
        "SELECT DISTINCT
                 bp.id_proveedor,
                 bp.cta_proveedor,
                 bp.id_banco,
                 b.nom_banco,
                 bp.ind_tipocuenta
           FROM  tab_det_cronopagos  d
           JOIN  tab_cuentasxpagar   f  ON f.id_factura    = d.id_factura
           JOIN  tab_bancoxprov      bp ON bp.id_proveedor = f.id_proveedor
           JOIN  tab_bancos          b  ON b.id_banco      = bp.id_banco
          WHERE  d.id_cronograma = :wid_cronograma
            AND  bp.ind_borrado  = FALSE
            AND  b.ind_borrado   = FALSE
            AND  b.ind_estado    = TRUE
          ORDER BY bp.id_proveedor, b.nom_banco, bp.cta_proveedor"
    );

    // ---- PROVEEDORES DE UN CRONOGRAMA SIN CUENTA UTILIZABLE ----
    // >>> CAMBIA: ahora también cuenta como "sin cuenta" el proveedor cuyas
    //     cuentas están todas en bancos borrados o inactivos, igual que el
    //     filtro de $list_ctas_prov_de_cronograma.
    $list_prov_sin_cuenta = $pdo->prepare(
        "SELECT DISTINCT
                 f.id_proveedor,
                 t.nom_tercero
           FROM  tab_det_cronopagos  d
           JOIN  tab_cuentasxpagar   f ON f.id_factura = d.id_factura
           JOIN  tab_terceros        t ON t.id_tercero = f.id_proveedor
          WHERE  d.id_cronograma = :wid_cronograma
            AND  NOT EXISTS (
                    SELECT 1
                      FROM tab_bancoxprov bp
                      JOIN tab_bancos     b ON b.id_banco = bp.id_banco
                     WHERE bp.id_proveedor = f.id_proveedor
                       AND bp.ind_borrado  = FALSE
                       AND b.ind_borrado   = FALSE
                       AND b.ind_estado    = TRUE
                 )
          ORDER BY t.nom_tercero"
    );

    // ---- LISTADO DE ARCHIVOS PLANOS (ENCABEZADO) ----
    $list_enc_archivo_plano = $pdo->prepare(
        "SELECT  a.id_archivo_plano,
                 a.nom_archivo,
                 a.id_empresa,
                 a.nom_empresa,
                 a.cta_empresa,
                 a.id_banco,
                 b.nom_banco,
                 a.ind_tipocuenta,
                 a.fecha_aplicacion,
                 a.id_tipo_pago,
                 tp.nom_tipo_pago,
                 a.fec_generacion,
                 a.ind_generado
           FROM  tab_enc_archivo_plano a
           JOIN  tab_bancos            b  ON b.id_banco      = a.id_banco
           JOIN  tab_tipos_pago        tp ON tp.id_tipo_pago = a.id_tipo_pago
          ORDER BY a.id_archivo_plano DESC"
    );

    // ---- UN ARCHIVO PLANO (ENCABEZADO) ----
    $get_enc_archivo_plano = $pdo->prepare(
        "SELECT  a.id_archivo_plano,
                 a.nom_archivo,
                 a.id_empresa,
                 a.nom_empresa,
                 a.cta_empresa,
                 a.id_banco,
                 b.nom_banco,
                 a.ind_tipocuenta,
                 a.fecha_aplicacion,
                 a.id_tipo_pago,
                 tp.nom_tipo_pago,
                 a.fec_generacion,
                 a.ind_generado
           FROM  tab_enc_archivo_plano a
           JOIN  tab_bancos            b  ON b.id_banco      = a.id_banco
           JOIN  tab_tipos_pago        tp ON tp.id_tipo_pago = a.id_tipo_pago
          WHERE  a.id_archivo_plano = :wid_archivo_plano"
    );

    // ---- DETALLE DE UN ARCHIVO PLANO ----
    // nom_tercero, id_tipo, banco y tipo de cuenta son la copia guardada el
    // día que se armó el archivo; no se vuelven a leer de los maestros.
    $list_det_archivo_plano = $pdo->prepare(
        "SELECT  d.id_archivo_plano,
                 d.id_cronograma,
                 d.id_factura,
                 d.id_cuota,
                 d.id_tipo,
                 d.id_proveedor,
                 d.nom_tercero,
                 d.id_banco,
                 b.nom_banco,
                 d.ind_tipocuenta,
                 d.cta_proveedor,
                 d.val_a_pagar,
                 d.concepto
           FROM  tab_det_archivo_plano d
           JOIN  tab_bancos            b ON b.id_banco = d.id_banco
          WHERE  d.id_archivo_plano = :wid_archivo_plano
          ORDER BY d.nom_tercero, d.id_factura, d.id_cuota"
    );

    // ---- TOTAL Y CANTIDAD DE REGISTROS (registro de control del archivo) ----
    $sum_det_archivo_plano = $pdo->prepare(
        "SELECT  COUNT(*)                        AS cant_registros,
                 COALESCE(SUM(val_a_pagar), 0)   AS total_a_debitar
           FROM  tab_det_archivo_plano
          WHERE  id_archivo_plano = :wid_archivo_plano"
    );

    // ---- INSERT — fun_insert_enc_archivo_plano (8 params) ----
    // Confirmada contra fun_inserts_tescxp.sql.
    // nom_archivo, id_empresa, nom_empresa, id_banco, ind_tipocuenta,
    // cta_empresa, fecha_aplicacion, id_tipo_pago
    // (id_archivo_plano se autogenera; fec_generacion queda NULL e
    //  ind_generado en FALSE)
    // id_banco e ind_tipocuenta deben ser los de la cuenta elegida: traerlos
    // con $get_cta_empresa, y que la función valide que coinciden con
    // tab_ctas_empresa.
    $ins_enc_archivo_plano = $pdo->prepare(
        "SELECT fun_insert_enc_archivo_plano(
            :wnom_archivo,
            :wid_empresa,
            :wnom_empresa,
            :wid_banco,
            :wind_tipocuenta,
            :wcta_empresa,
            :wfecha_aplicacion,
            :wid_tipo_pago
        )"
    );

    // ---- INSERT — fun_insert_det_archivo_plano (11 params) ----
    // Confirmada contra fun_inserts_tescxp.sql.
    // id_archivo_plano, id_cronograma, id_factura, id_cuota, id_tipo,
    // id_proveedor, nom_tercero, id_banco, ind_tipocuenta, cta_proveedor,
    // concepto (concepto admite NULL)
    // id_banco e ind_tipocuenta deben ser los de la cuenta elegida
    // ($list_ctas_prov_de_cronograma); la función rechaza si no coinciden.
    // (val_a_pagar lo pone trg_val_a_pagar_archivo_plano desde tab_det_cronopagos)
    $ins_det_archivo_plano = $pdo->prepare(
        "SELECT fun_insert_det_archivo_plano(
            :wid_archivo_plano,
            :wid_cronograma,
            :wid_factura,
            :wid_cuota,
            :wid_tipo,
            :wid_proveedor,
            :wnom_tercero,
            :wid_banco,
            :wind_tipocuenta,
            :wcta_proveedor,
            :wconcepto
        )"
    );

    // ---- UPDATE — fun_update_enc_archivo_plano (3 params) ----
    // id_archivo_plano, id_banco, nom_archivo — solo si no está generado.
    // OJO: si se cambia id_banco aquí, deja de coincidir con el banco de
    // cta_empresa. Conviene que la función solo permita cambiar el nombre, o
    // que cambie la cuenta completa.
    $upd_enc_archivo_plano = $pdo->prepare(
        "SELECT fun_update_enc_archivo_plano(
            :wid_archivo_plano,
            :wid_banco,
            :wnom_archivo
        )"
    );

    // ---- ID DEL ARCHIVO PLANO RECIÉN CREADO ----
    // >>> NUEVO. fun_insert_enc_archivo_plano devuelve TRUE, no el id. Se busca
    //     el último encabezado sin generar con ese nombre y esa cuenta, dentro
    //     de la misma transacción del insert.
    $get_id_archivo_recien_creado = $pdo->prepare(
        "SELECT  MAX(id_archivo_plano)
           FROM  tab_enc_archivo_plano
          WHERE  nom_archivo  = :wnom_archivo
            AND  id_empresa   = :wid_empresa
            AND  cta_empresa  = :wcta_empresa
            AND  ind_generado = FALSE"
    );

    // ---- MARCAR ARCHIVO PLANO COMO GENERADO (al descargarlo) ----
    // >>> CAMBIA: fec_generacion ya la pone trg_fecha_generacion_archivo al
    //     pasar ind_generado de FALSE a TRUE; aquí solo se cambia el indicador.
    //     El filtro ind_generado = FALSE hace que descargarlo otra vez no haga nada.
    // fec_generacion se pone aquí mismo (fecha de la primera descarga), sin
    // depender de trg_fecha_generacion_archivo: si el trigger no existe en la
    // base, el archivo quedaba "Generado" pero sin fecha. Volver a descargar
    // no cambia la fecha (solo actualiza si ind_generado sigue en FALSE).
    $upd_generar_archivo_plano = $pdo->prepare(
        "UPDATE tab_enc_archivo_plano
            SET ind_generado   = TRUE,
                fec_generacion = CURRENT_DATE
          WHERE id_archivo_plano = :wid_archivo_plano
            AND ind_generado     = FALSE"
    );

    // =========================================================================
    // 10. TAB_CODIGOS_RESPUESTA_BANCO                               (Tabla 14)
    // =========================================================================
    // >>> CAMBIA todo el bloque (antes tab_motivos_rechazo).
    // Catálogo de los códigos que devuelve cada banco en su archivo de
    // respuesta. PK (id_codigo, id_banco): dos bancos pueden usar el mismo
    // código con significados distintos. El banco que responde es el de la
    // cuenta de origen del archivo plano (tab_enc_archivo_plano.id_banco).

    // ---- LISTADO DE ADMINISTRACIÓN (incluye inactivos, para reactivarlos) ----
    $list_codigos_respuesta = $pdo->prepare(
        "SELECT  c.id_codigo,
                 c.id_banco,
                 b.nom_banco,
                 c.des_motivo,
                 c.ind_borrado
           FROM  tab_codigos_respuesta_banco c
           JOIN  tab_bancos                  b ON b.id_banco = c.id_banco
          ORDER BY b.nom_banco, c.ind_borrado, c.id_codigo"
    );

    // ---- CÓDIGOS DE UN BANCO (incluye inactivos) ----
    $list_codigos_de_banco = $pdo->prepare(
        "SELECT  id_codigo,
                 des_motivo,
                 ind_borrado
           FROM  tab_codigos_respuesta_banco
          WHERE  id_banco = :wid_banco
          ORDER BY ind_borrado, id_codigo"
    );

    // ---- CÓDIGOS ACTIVOS DEL BANCO DE UN ARCHIVO PLANO (combo al registrar la respuesta) ----
    $list_codigos_de_archivo = $pdo->prepare(
        "SELECT  c.id_codigo,
                 c.des_motivo
           FROM  tab_enc_archivo_plano       a
           JOIN  tab_codigos_respuesta_banco c ON c.id_banco = a.id_banco
          WHERE  a.id_archivo_plano = :wid_archivo_plano
            AND  c.ind_borrado      = FALSE
          ORDER BY c.id_codigo"
    );

    // ---- UN CÓDIGO (también sirve para traducir el código al importar la respuesta) ----
    $get_codigo_respuesta = $pdo->prepare(
        "SELECT  c.id_codigo,
                 c.id_banco,
                 b.nom_banco,
                 c.des_motivo,
                 c.ind_borrado
           FROM  tab_codigos_respuesta_banco c
           JOIN  tab_bancos                  b ON b.id_banco = c.id_banco
          WHERE  c.id_codigo = :wid_codigo
            AND  c.id_banco  = :wid_banco"
    );

    // ---- INSERT — fun_insert_codigos_respuesta_banco (3 params) ----
    // id_codigo (el que manda el banco), id_banco, des_motivo
    // (ind_borrado entra en FALSE por DEFAULT)
    $ins_codigo_respuesta = $pdo->prepare(
        "SELECT fun_insert_codigos_respuesta_banco(
            :wid_codigo,
            :wid_banco,
            :wdes_motivo
        )"
    );

    // ---- UPDATE — fun_update_codigos_respuesta_banco (4 params) ----
    // id_codigo, id_banco (identifican el registro), des_motivo, ind_borrado
    // (ind_borrado = FALSE reactiva un código dado de baja)
    $upd_codigo_respuesta = $pdo->prepare(
        "SELECT fun_update_codigos_respuesta_banco(
            :wid_codigo,
            :wid_banco,
            :wdes_motivo,
            :wind_borrado
        )"
    );

    // ---- DELETE — fun_delete_codigos_respuesta_banco (2 params) — borrado lógico ----
    $del_codigo_respuesta = $pdo->prepare(
        "SELECT fun_delete_codigos_respuesta_banco(
            :wid_codigo,
            :wid_banco
        )"
    );

    // ---- ¿EL CÓDIGO YA SE USÓ EN ALGÚN PAGO? (informativo) ----
    $check_codigo_en_uso = $pdo->prepare(
        "SELECT  EXISTS (
                    SELECT 1
                      FROM tab_pagos_cxp
                     WHERE id_codigo = :wid_codigo
                       AND id_banco  = :wid_banco
                 ) AS en_uso"
    );

    // =========================================================================
    // 11. TAB_PAGOS_CXP                                             (Tabla 15)
    // =========================================================================
    // >>> CAMBIA todo el bloque.
    // Un registro por respuesta del banco a una línea de archivo plano.
    //   - estado_pago: 1 = PENDIENTE, 2 = APROBADO, 3 = RECHAZADO.
    //   - id_codigo e id_banco son NOT NULL: el pago se registra cuando llega
    //     la respuesta del banco, con su código.
    //   - Al quedar APROBADO (2), fun_insert_pagos_cxp / fun_update_pagos_cxp
    //     marcan la cuota como pagada y cierran el cronograma si ya no le
    //     quedan cuotas sin pagar. Los triggers hacen el resto:
    //       cuota pagada  -> trg_actualizar_saldo_factura   (saldo y cierre de factura)
    //       saldo factura -> trg_actualizar_saldo_proveedor (deuda del proveedor)
    //   - RECHAZADO (3): la cuota vuelve a quedar disponible para otro archivo
    //     plano (ver $list_cuotas_de_cronograma).

    // ---- LISTADO GENERAL ----
    $list_pagos_cxp = $pdo->prepare(
        "SELECT  p.id_pago,
                 p.id_factura,
                 p.id_cuota,
                 f.id_proveedor,
                 t.nom_tercero,
                 p.id_archivo_plano,
                 p.id_cronograma,
                 p.fec_pago,
                 p.val_pago,
                 p.estado_pago,
                 CASE p.estado_pago WHEN 1 THEN 'PENDIENTE'
                                    WHEN 2 THEN 'APROBADO'
                                    WHEN 3 THEN 'RECHAZADO' END AS nom_estado_pago,
                 p.id_codigo,
                 p.id_banco,
                 c.des_motivo
           FROM  tab_pagos_cxp               p
           JOIN  tab_cuentasxpagar           f ON f.id_factura = p.id_factura
           JOIN  tab_terceros                t ON t.id_tercero = f.id_proveedor
           JOIN  tab_codigos_respuesta_banco c ON c.id_codigo  = p.id_codigo
                                              AND c.id_banco   = p.id_banco
          ORDER BY p.fec_pago DESC, p.id_pago DESC"
    );

    // ---- UN PAGO ----
    $get_pago_cxp = $pdo->prepare(
        "SELECT  p.id_pago,
                 p.id_factura,
                 p.id_cuota,
                 f.id_proveedor,
                 t.nom_tercero,
                 p.id_archivo_plano,
                 p.id_cronograma,
                 p.fec_pago,
                 p.val_pago,
                 p.estado_pago,
                 CASE p.estado_pago WHEN 1 THEN 'PENDIENTE'
                                    WHEN 2 THEN 'APROBADO'
                                    WHEN 3 THEN 'RECHAZADO' END AS nom_estado_pago,
                 p.id_codigo,
                 p.id_banco,
                 c.des_motivo
           FROM  tab_pagos_cxp               p
           JOIN  tab_cuentasxpagar           f ON f.id_factura = p.id_factura
           JOIN  tab_terceros                t ON t.id_tercero = f.id_proveedor
           JOIN  tab_codigos_respuesta_banco c ON c.id_codigo  = p.id_codigo
                                              AND c.id_banco   = p.id_banco
          WHERE  p.id_pago = :wid_pago"
    );

    // ---- PAGOS POR ESTADO (1, 2 o 3) ----
    $list_pagos_por_estado = $pdo->prepare(
        "SELECT  p.id_pago,
                 p.id_factura,
                 p.id_cuota,
                 f.id_proveedor,
                 t.nom_tercero,
                 p.id_archivo_plano,
                 p.id_cronograma,
                 p.fec_pago,
                 p.val_pago,
                 p.id_codigo,
                 c.des_motivo
           FROM  tab_pagos_cxp               p
           JOIN  tab_cuentasxpagar           f ON f.id_factura = p.id_factura
           JOIN  tab_terceros                t ON t.id_tercero = f.id_proveedor
           JOIN  tab_codigos_respuesta_banco c ON c.id_codigo  = p.id_codigo
                                              AND c.id_banco   = p.id_banco
          WHERE  p.estado_pago = :westado_pago
          ORDER BY p.fec_pago DESC, p.id_pago DESC"
    );

    // ---- HISTORIAL DE INTENTOS DE UNA CUOTA ----
    $list_pagos_de_cuota = $pdo->prepare(
        "SELECT  p.id_pago,
                 p.id_archivo_plano,
                 p.id_cronograma,
                 p.fec_pago,
                 p.val_pago,
                 p.estado_pago,
                 CASE p.estado_pago WHEN 1 THEN 'PENDIENTE'
                                    WHEN 2 THEN 'APROBADO'
                                    WHEN 3 THEN 'RECHAZADO' END AS nom_estado_pago,
                 p.id_codigo,
                 c.des_motivo
           FROM  tab_pagos_cxp               p
           JOIN  tab_codigos_respuesta_banco c ON c.id_codigo = p.id_codigo
                                              AND c.id_banco  = p.id_banco
          WHERE  p.id_factura = :wid_factura
            AND  p.id_cuota   = :wid_cuota
          ORDER BY p.id_pago DESC"
    );

    // ---- VALIDACIÓN — ¿LA CUOTA YA TIENE UN PAGO APROBADO? ----
    $check_cuota_pago_aprobado = $pdo->prepare(
        "SELECT  EXISTS (
                    SELECT 1
                      FROM tab_pagos_cxp
                     WHERE id_factura  = :wid_factura
                       AND id_cuota    = :wid_cuota
                       AND estado_pago = 2
                 ) AS ya_pagada"
    );

    // ---- CONCILIACIÓN — LÍNEAS DE UN ARCHIVO CON SU RESPUESTA ----
    // id_pago NULL = la línea todavía no tiene respuesta del banco.
    $list_conciliacion_archivo = $pdo->prepare(
        "SELECT  d.id_archivo_plano,
                 d.id_cronograma,
                 d.id_factura,
                 d.id_cuota,
                 d.id_proveedor,
                 d.nom_tercero,
                 d.cta_proveedor,
                 d.val_a_pagar,
                 p.id_pago,
                 p.estado_pago,
                 CASE p.estado_pago WHEN 1 THEN 'PENDIENTE'
                                    WHEN 2 THEN 'APROBADO'
                                    WHEN 3 THEN 'RECHAZADO' END AS nom_estado_pago,
                 p.id_codigo,
                 c.des_motivo
           FROM  tab_det_archivo_plano d
           LEFT JOIN tab_pagos_cxp     p ON p.id_archivo_plano = d.id_archivo_plano
                                        AND p.id_cronograma    = d.id_cronograma
                                        AND p.id_factura       = d.id_factura
                                        AND p.id_cuota         = d.id_cuota
           LEFT JOIN tab_codigos_respuesta_banco c ON c.id_codigo = p.id_codigo
                                                  AND c.id_banco  = p.id_banco
          WHERE  d.id_archivo_plano = :wid_archivo_plano
          ORDER BY d.nom_tercero, d.id_factura, d.id_cuota"
    );

    // ---- ¿ESA LÍNEA YA TIENE UN PAGO REGISTRADO? ----
    // Evita duplicar si la misma respuesta del banco se importa dos veces.
    // Si existe y está en 1 (PENDIENTE), se usa $upd_estado_pago_cxp.
    $check_pago_de_linea = $pdo->prepare(
        "SELECT  id_pago, estado_pago
           FROM  tab_pagos_cxp
          WHERE  id_archivo_plano = :wid_archivo_plano
            AND  id_factura       = :wid_factura
            AND  id_cuota         = :wid_cuota"
    );

    // ---- INSERT — fun_insert_pagos_cxp (6 params) ----
    // id_archivo_plano, id_factura, id_cuota, fec_pago, estado_pago (1, 2 o 3),
    // id_codigo
    // La función toma de la línea del archivo plano id_cronograma y val_pago
    // (val_a_pagar), y del encabezado el id_banco. Exige que el archivo esté
    // generado y que el código exista y esté activo para ese banco.
    // Si estado_pago = 2, marca la cuota pagada y cierra el cronograma.
    $ins_pago_cxp = $pdo->prepare(
        "SELECT fun_insert_pagos_cxp(
            :wid_archivo_plano,
            :wid_factura,
            :wid_cuota,
            :wfec_pago,
            :westado_pago,
            :wid_codigo
        )"
    );

    // ---- UPDATE — fun_update_pagos_cxp (3 params) ----
    // id_pago, estado_pago (2 o 3), id_codigo
    // Solo sobre pagos en 1 (PENDIENTE). Si queda en 2, marca la cuota pagada y
    // cierra el cronograma, igual que el insert.
    $upd_estado_pago_cxp = $pdo->prepare(
        "SELECT fun_update_pagos_cxp(
            :wid_pago,
            :westado_pago,
            :wid_codigo
        )"
    );

    // =========================================================================
    // 12. TAB_BANCOS  (catálogo compartido)
    // =========================================================================

    // ---- LISTADO (bancos.php) ----
    $list_bancos_full = $pdo->prepare(
        "SELECT  id_banco,
                 nom_banco,
                 ind_estado
           FROM  tab_bancos
          WHERE  ind_borrado = FALSE
          ORDER BY nom_banco ASC"
    );

    // ---- UN BANCO ----
    $get_banco = $pdo->prepare(
        "SELECT  id_banco,
                 nom_banco,
                 ind_estado
           FROM  tab_bancos
          WHERE  id_banco    = :wid_banco
            AND  ind_borrado = FALSE"
    );

    // ---- INSERT — fun_insert_bancos (3 params) ----
    $ins_banco = $pdo->prepare(
        "SELECT fun_insert_bancos(:wid_banco, :wnom_banco, :wind_estado)"
    );

    // ---- UPDATE — fun_update_bancos (3 params) ----
    $upd_banco = $pdo->prepare(
        "SELECT fun_update_bancos(:wid_banco, :wnom_banco, :wind_estado)"
    );

    // ---- DELETE — fun_delete_bancos (1 param) — borrado lógico ----
    $del_banco = $pdo->prepare(
        "SELECT fun_delete_bancos(:wid_banco)"
    );

    // ---- VALIDACIÓN — ¿EL BANCO ESTÁ EN USO? ----
    // Las dos primeras bloquean el borrado (fun_delete_bancos); las otras son
    // informativas.
    // >>> CAMBIA: se agregó en_codigos_respuesta.
    // PDO_PGSQL no permite repetir un placeholder: mandar el mismo valor en
    // :wid_banco, :wid_banco2, :wid_banco3 y :wid_banco4.
    $check_banco_en_uso = $pdo->prepare(
        "SELECT  EXISTS (SELECT 1 FROM tab_ctas_empresa
                          WHERE id_banco = :wid_banco  AND ind_borrado = FALSE) AS en_ctas_empresa,
                 EXISTS (SELECT 1 FROM tab_bancoxprov
                          WHERE id_banco = :wid_banco2 AND ind_borrado = FALSE) AS en_ctas_proveedor,
                 EXISTS (SELECT 1 FROM tab_enc_archivo_plano
                          WHERE id_banco = :wid_banco3)                         AS en_archivos_planos,
                 EXISTS (SELECT 1 FROM tab_codigos_respuesta_banco
                          WHERE id_banco = :wid_banco4 AND ind_borrado = FALSE) AS en_codigos_respuesta"
    );

} catch (PDOException $e) {
    error_log("Error en prepare_tescxp.php: " . $e->getMessage());
    die("Error crítico al preparar consultas. Revise los logs del servidor.");
}
?>
