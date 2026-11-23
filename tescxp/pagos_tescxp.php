<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Historial de Pagos";
$page_description = "Pagos registrados con la respuesta del banco: proveedores, nómina e inversiones";
$page_icon        = "bi-receipt";
$page_extra_css   = ['modules/tescxp/css/tcx_pantalla.css', 'modules/tescxp/css/tcx_modales.css', 'modules/tescxp/css/pagos_tescxp.css'];
$page_extra_js    = ['modules/tescxp/js/pagos_tescxp.js'];
$page_erp_ui      = ['modales', 'indicadores', 'filtros', 'paginador', 'lista_fija', 'movil', 'botones', 'orden'];   // GUIA_PANTALLAS_ERP §2
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// RESPONDER JSON
// ------------------------------------------------------------
// menu_principal.php ya imprimió el layout antes de incluir esta página:
// se descarta todo lo que haya en los buffers y se envía SOLO el JSON.
// ============================================================
if (!function_exists('responder_json')) {
    function responder_json(array $respuesta): void {
        $previo = '';
        while (ob_get_level() > 0) {
            $previo = ((string)ob_get_clean()) . $previo;
        }
        $previo = trim(strip_tags($previo));
        if ($previo !== '' && preg_match('/(fatal|error|warning|notice|deprecated|exception)/i', $previo)) {
            $respuesta['debug_salida_previa'] = substr($previo, 0, 800);
        }
        if (!headers_sent()) {
            header('Content-Type: application/json; charset=utf-8');
        }
        echo json_encode($respuesta, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
        exit;
    }
}

// PostgreSQL devuelve los booleanos vía PDO como 't' / 'f' (o true/false).
if (!function_exists('es_verdadero')) {
    function es_verdadero($valor): bool {
        return in_array($valor, ['t', 'T', 'true', 'TRUE', '1', 1, true], true);
    }
}

// ="900123456" (formato texto para Excel) -> 900123456
function limpiar_celda($valor): string {
    $v = trim((string)$valor);
    if (preg_match('/^="(.*)"$/s', $v, $m) || preg_match('/^=([0-9A-Za-z]+)$/', $v, $m)) {
        $v = trim($m[1]);
    }
    return $v;
}

// Acepta AAAA-MM-DD o DD/MM/AAAA (si alguien guardó la respuesta desde Excel)
function fecha_iso(string $f): ?string {
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $f)) {
        $d = DateTime::createFromFormat('Y-m-d', $f);
        return ($d && $d->format('Y-m-d') === $f) ? $f : null;
    }
    if (preg_match('/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/', $f, $m)) {
        return checkdate((int)$m[2], (int)$m[1], (int)$m[3])
            ? sprintf('%04d-%02d-%02d', $m[3], $m[2], $m[1]) : null;
    }
    return null;
}

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    erp_validar_csrf();   // SEC-08: token de la sesión + origen
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- VER DETALLE DE UN PAGO ----------
        if (isset($_POST['btn_ver_pago'])) {
            $id_pago = trim($_POST['hid_id_pago'] ?? '');

            if ($id_pago === '' || !ctype_digit($id_pago)) {
                throw new Exception('Pago no válido.');
            }

            $get_pago_cxp->execute([':wid_pago' => (int)$id_pago]);
            $pago = $get_pago_cxp->fetch(PDO::FETCH_ASSOC);

            if (!$pago) {
                throw new Exception('El pago no existe.');
            }

            $respuesta['success'] = true;
            $respuesta['pago']    = $pago;
            responder_json($respuesta);
        }

        // ---------- APLICAR RESPUESTA DEL BANCO (CSV) ----------
        // El archivo plano que se envía al banco NO lleva factura ni cuota, así
        // que el banco identifica cada pago por su CONSECUTIVO: la posición de
        // la línea dentro del archivo (1, 2, 3...). Aquí se vuelve a leer el
        // detalle con $list_det_archivo_plano, que tiene el MISMO orden que la
        // descarga (nom_tercero, id_factura, id_cuota), y la línea N es la
        // fila N. Además se comparan documento, cuenta y valor, para no aplicar
        // la respuesta a otro pago si el orden no coincide.
        //
        // El valor del pago NUNCA se toma del archivo del banco: lo pone
        // fun_insert_pagos_cxp desde tab_det_archivo_plano.val_a_pagar.
        //
        // El tipo del archivo (PROVEEDORES / NOMINA / INVERSION) no está en el
        // encabezado: lo calcula $get_enc_archivo_plano según su tabla de detalle.
        //
        // ARCHIVOS DE NÓMINA: las líneas salen de $list_det_archivo_nomina
        // (mismo orden que la descarga), el documento es el del empleado y el
        // pago se registra con fun_insert_pagos_nomina, que deja la nómina del
        // empleado PAGADA (2) o RECHAZADA (3) en tab_nomina.
        //
        // ARCHIVOS DE INVERSIONES: igual, con $list_det_archivo_inversion; el
        // documento es el del inversor y fun_insert_pagos_inversion deja la
        // cuota PAGADA (2) o RECHAZADA (3) en tab_cuotas_inversion (Financiero).
        if (isset($_POST['btn_importar'])) {
            $filas = json_decode($_POST['hid_filas_importar'] ?? '', true);

            if (!is_array($filas) || count($filas) === 0) {
                throw new Exception('No se recibió ninguna fila para aplicar.');
            }

            $aplicadas = 0;
            $aplicadas_tipo = ['proveedores' => 0, 'nomina' => 0, 'inversiones' => 0];   // para abrir la pestaña que corresponde
            $omitidas  = [];
            $detalles  = [];   // id_archivo_plano => líneas en el orden de la descarga

            $pdo->beginTransaction();

            foreach ($filas as $f) {
                $id_archivo = limpiar_celda($f['id_archivo_plano'] ?? '');
                $consec     = limpiar_celda($f['consecutivo'] ?? '');
                $estado_txt = strtoupper(limpiar_celda($f['estado'] ?? ''));
                $id_codigo  = limpiar_celda($f['codigo_respuesta'] ?? '');
                $fec_txt    = limpiar_celda($f['fecha_pago'] ?? '');
                $doc        = limpiar_celda($f['documento_proveedor'] ?? '');
                $cuenta     = limpiar_celda($f['cuenta_destino'] ?? '');
                $valor      = limpiar_celda($f['valor_a_pagar'] ?? '');

                $etiqueta = "Archivo {$id_archivo} / línea {$consec}";

                if (!ctype_digit($id_archivo) || !ctype_digit($consec) || (int)$consec < 1) {
                    $omitidas[] = "{$etiqueta}: ID de archivo o consecutivo no válido.";
                    continue;
                }

                // 2 = APROBADO, 3 = RECHAZADO (1 = PENDIENTE no llega en una respuesta)
                $estados = ['APROBADO' => 2, 'RECHAZADO' => 3];
                if (!isset($estados[$estado_txt])) {
                    $omitidas[] = "{$etiqueta}: el estado '{$estado_txt}' no es APROBADO ni RECHAZADO.";
                    continue;
                }
                $estado_pago = $estados[$estado_txt];

                // id_codigo VARCHAR(10), obligatorio también en los aprobados
                if ($id_codigo === '' || strlen($id_codigo) > 10) {
                    $omitidas[] = "{$etiqueta}: falta el código de respuesta del banco o supera 10 caracteres.";
                    continue;
                }

                $fec_pago = $fec_txt === '' ? date('Y-m-d') : fecha_iso($fec_txt);
                if ($fec_pago === null) {
                    $omitidas[] = "{$etiqueta}: la fecha de pago '{$fec_txt}' no es válida (use AAAA-MM-DD).";
                    continue;
                }

                // Detalle del archivo, una sola consulta por archivo. Primero se
                // mira de qué es (proveedores, nómina o inversiones).
                if (!isset($detalles[$id_archivo])) {
                    $get_enc_archivo_plano->execute([':wid_archivo_plano' => (int)$id_archivo]);
                    $enc_imp = $get_enc_archivo_plano->fetch(PDO::FETCH_ASSOC);
                    $tipo    = $enc_imp ? (string)$enc_imp['tipo_archivo'] : '';

                    if ($tipo === 'NOMINA') {
                        $list_det_archivo_nomina->execute([':wid_archivo_plano' => (int)$id_archivo]);
                        $lineas = $list_det_archivo_nomina->fetchAll(PDO::FETCH_ASSOC);
                    } elseif ($tipo === 'INVERSION') {
                        $list_det_archivo_inversion->execute([':wid_archivo_plano' => (int)$id_archivo]);
                        $lineas = $list_det_archivo_inversion->fetchAll(PDO::FETCH_ASSOC);
                    } elseif ($enc_imp) {
                        $list_det_archivo_plano->execute([':wid_archivo_plano' => (int)$id_archivo]);
                        $lineas = $list_det_archivo_plano->fetchAll(PDO::FETCH_ASSOC);
                    } else {
                        $lineas = [];
                    }
                    $detalles[$id_archivo] = ['tipo' => $tipo, 'lineas' => $lineas];
                }
                $es_nomina    = $detalles[$id_archivo]['tipo'] === 'NOMINA';
                $es_inversion = $detalles[$id_archivo]['tipo'] === 'INVERSION';
                $detalle      = $detalles[$id_archivo]['lineas'];

                if (empty($detalle)) {
                    $omitidas[] = "{$etiqueta}: el archivo plano {$id_archivo} no existe o no tiene pagos.";
                    continue;
                }

                $linea = $detalle[(int)$consec - 1] ?? null;
                if (!$linea) {
                    $omitidas[] = "{$etiqueta}: el archivo plano solo tiene " . count($detalle) . " línea(s).";
                    continue;
                }

                // Documento y cuenta del beneficiario: proveedor, empleado o inversor
                if ($es_nomina) {
                    $doc_linea    = trim((string)$linea['id_empleado']);
                    $cuenta_linea = trim((string)$linea['num_cuenta']);
                } elseif ($es_inversion) {
                    $doc_linea    = trim((string)$linea['id_inversor']);
                    $cuenta_linea = trim((string)$linea['num_cuenta']);
                } else {
                    $doc_linea    = trim((string)$linea['id_proveedor']);
                    $cuenta_linea = trim((string)$linea['cta_proveedor']);
                }

                // Control cruzado: la línea N del ERP debe ser el mismo pago que respondió el banco
                if ($doc !== '' && $doc !== $doc_linea) {
                    $omitidas[] = "{$etiqueta}: el documento {$doc} no coincide con el de esa línea ({$doc_linea}).";
                    continue;
                }
                if ($cuenta !== '' && $cuenta !== $cuenta_linea) {
                    $omitidas[] = "{$etiqueta}: la cuenta {$cuenta} no coincide con la de esa línea ({$cuenta_linea}).";
                    continue;
                }
                if ($valor !== '' && (!is_numeric($valor) || abs((float)$valor - (float)$linea['val_a_pagar']) > 0.5)) {
                    $omitidas[] = "{$etiqueta}: el valor {$valor} no coincide con el de esa línea (" . number_format((float)$linea['val_a_pagar'], 0, '', '') . ").";
                    continue;
                }

                // ---------- LÍNEA DE NÓMINA ----------
                if ($es_nomina) {
                    $clave_nom = [
                        ':wid_archivo_plano' => (int)$id_archivo,
                        ':wano_nomina'       => (int)$linea['ano_nomina'],
                        ':wmes_nomina'       => (int)$linea['mes_nomina'],
                        ':wval_periodo'      => (int)$linea['val_periodo'],
                        ':wid_empleado'      => $linea['id_empleado'],
                    ];
                    $check_pago_nomina_de_linea->execute($clave_nom);
                    $previo = $check_pago_nomina_de_linea->fetch(PDO::FETCH_ASSOC);

                    if ($previo && (int)$previo['estado_pago'] !== 1) {
                        $ya = (int)$previo['estado_pago'] === 2 ? 'APROBADO' : 'RECHAZADO';
                        $omitidas[] = "{$etiqueta}: ya tiene respuesta registrada ({$ya}).";
                        continue;
                    }

                    $pdo->exec('SAVEPOINT sp_fila');
                    try {
                        if ($previo) {
                            $upd_estado_pago_nomina->execute([
                                ':wid_pago_nomina' => (int)$previo['id_pago_nomina'],
                                ':westado_pago'    => $estado_pago,
                                ':wid_codigo'      => $id_codigo,
                            ]);
                        } else {
                            $ins_pago_nomina->execute($clave_nom + [
                                ':wfec_pago'    => $fec_pago,
                                ':westado_pago' => $estado_pago,
                                ':wid_codigo'   => $id_codigo,
                            ]);
                        }
                        $pdo->exec('RELEASE SAVEPOINT sp_fila');
                    } catch (Throwable $e) {
                        $pdo->exec('ROLLBACK TO SAVEPOINT sp_fila');
                        $omitidas[] = "{$etiqueta} (nómina de {$linea['nom_empleado']}): " . limpiar_error_pgsql($e->getMessage());
                        continue;
                    }

                    $aplicadas++;
                    $aplicadas_tipo['nomina']++;
                    continue;
                }

                // ---------- LÍNEA DE INVERSIONES ----------
                if ($es_inversion) {
                    $clave_inv = [
                        ':wid_archivo_plano' => (int)$id_archivo,
                        ':wid_proyecto'      => $linea['id_proyecto'],
                        ':wid_inversor'      => $linea['id_inversor'],
                        ':wid_cuota'         => (int)$linea['id_cuota'],
                    ];
                    $check_pago_inversion_de_linea->execute($clave_inv);
                    $previo = $check_pago_inversion_de_linea->fetch(PDO::FETCH_ASSOC);

                    if ($previo && (int)$previo['estado_pago'] !== 1) {
                        $ya = (int)$previo['estado_pago'] === 2 ? 'APROBADO' : 'RECHAZADO';
                        $omitidas[] = "{$etiqueta}: ya tiene respuesta registrada ({$ya}).";
                        continue;
                    }

                    $pdo->exec('SAVEPOINT sp_fila');
                    try {
                        if ($previo) {
                            $upd_estado_pago_inversion->execute([
                                ':wid_pago_inversion' => (int)$previo['id_pago_inversion'],
                                ':westado_pago'       => $estado_pago,
                                ':wid_codigo'         => $id_codigo,
                            ]);
                        } else {
                            $ins_pago_inversion->execute($clave_inv + [
                                ':wfec_pago'    => $fec_pago,
                                ':westado_pago' => $estado_pago,
                                ':wid_codigo'   => $id_codigo,
                            ]);
                        }
                        $pdo->exec('RELEASE SAVEPOINT sp_fila');
                    } catch (Throwable $e) {
                        $pdo->exec('ROLLBACK TO SAVEPOINT sp_fila');
                        $omitidas[] = "{$etiqueta} (inversión {$linea['id_proyecto']} cuota {$linea['id_cuota']} de {$linea['nom_inversor']}): " . limpiar_error_pgsql($e->getMessage());
                        continue;
                    }

                    $aplicadas++;
                    $aplicadas_tipo['inversiones']++;
                    continue;
                }

                // ¿Esa línea ya tiene respuesta? Si está PENDIENTE (1) se actualiza;
                // si ya está resuelta, se omite (archivo importado dos veces).
                $check_pago_de_linea->execute([
                    ':wid_archivo_plano' => (int)$id_archivo,
                    ':wid_factura'       => (int)$linea['id_factura'],
                    ':wid_cuota'         => (int)$linea['id_cuota'],
                ]);
                $previo = $check_pago_de_linea->fetch(PDO::FETCH_ASSOC);

                if ($previo && (int)$previo['estado_pago'] !== 1) {
                    $ya = (int)$previo['estado_pago'] === 2 ? 'APROBADO' : 'RECHAZADO';
                    $omitidas[] = "{$etiqueta}: ya tiene respuesta registrada ({$ya}).";
                    continue;
                }

                // Cada fila en su propio SAVEPOINT: si la base la rechaza, solo se
                // revierte esa fila y el motivo queda en "omitidas".
                $pdo->exec('SAVEPOINT sp_fila');
                try {
                    if ($previo) {
                        $upd_estado_pago_cxp->execute([
                            ':wid_pago'     => (int)$previo['id_pago'],
                            ':westado_pago' => $estado_pago,
                            ':wid_codigo'   => $id_codigo,
                        ]);
                    } else {
                        $ins_pago_cxp->execute([
                            ':wid_archivo_plano' => (int)$id_archivo,
                            ':wid_factura'       => (int)$linea['id_factura'],
                            ':wid_cuota'         => (int)$linea['id_cuota'],
                            ':wfec_pago'         => $fec_pago,
                            ':westado_pago'      => $estado_pago,
                            ':wid_codigo'        => $id_codigo,
                        ]);
                    }
                    $pdo->exec('RELEASE SAVEPOINT sp_fila');
                } catch (Throwable $e) {
                    $pdo->exec('ROLLBACK TO SAVEPOINT sp_fila');
                    $omitidas[] = "{$etiqueta} (factura {$linea['id_factura']}, cuota {$linea['id_cuota']}): "
                                . limpiar_error_pgsql($e->getMessage());
                    continue;
                }

                $aplicadas++;
                $aplicadas_tipo['proveedores']++;
            }

            $pdo->commit();

            $respuesta['success']   = $aplicadas > 0;
            $respuesta['aplicadas'] = $aplicadas;
            $respuesta['aplicadas_tipo'] = $aplicadas_tipo;
            $respuesta['omitidas']  = $omitidas;
            $respuesta['message']   = $aplicadas > 0
                ? "Se registraron {$aplicadas} pago(s) a partir de la respuesta del banco." . (count($omitidas) ? ' ' . count($omitidas) . ' fila(s) omitida(s).' : '')
                : 'Ninguna fila se pudo aplicar.';
            responder_json($respuesta);
        }

        $respuesta['message'] = 'Acción no válida.';
        responder_json($respuesta);

    } catch (Throwable $e) {
        if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
            $pdo->rollBack();
        }
        $mensaje = limpiar_error_pgsql($e->getMessage());
        if (empty($mensaje)) {
            $mensaje = $e->getMessage();
        }
        $respuesta['message'] = $mensaje;
        responder_json($respuesta);
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
// $list_pagos_cxp trae estado_pago numérico (1, 2, 3) y nom_estado_pago
// ('PENDIENTE', 'APROBADO', 'RECHAZADO'); la vista usa el nombre.
// Tres secciones: pagos de proveedores (tab_pagos_cxp), de nómina
// (tab_pagos_nomina) y de inversiones (tab_pagos_inversion). Los id_pago de
// las tablas se repiten, así que cada fila lleva una clave única
// (CXP-12 / NOM-12 / INV-12) para el detalle en el JS.
$list_pagos_cxp->execute();
$pagos_prov = [];
foreach ($list_pagos_cxp->fetchAll(PDO::FETCH_ASSOC) as $p) {
    $p['tipo_pago'] = 'CXP';
    $p['clave']     = 'CXP-' . (int)$p['id_pago'];
    $pagos_prov[] = $p;
}
$pagos_nom = [];
if (isset($list_pagos_nomina) && $list_pagos_nomina instanceof PDOStatement) {
    $list_pagos_nomina->execute();
    foreach ($list_pagos_nomina->fetchAll(PDO::FETCH_ASSOC) as $p) {
        $p['clave'] = 'NOM-' . (int)$p['id_pago'];
        $pagos_nom[] = $p;
    }
}
$pagos_inv = [];
if (isset($list_pagos_inversion) && $list_pagos_inversion instanceof PDOStatement) {
    $list_pagos_inversion->execute();
    foreach ($list_pagos_inversion->fetchAll(PDO::FETCH_ASSOC) as $p) {
        $p['clave'] = 'INV-' . (int)$p['id_pago'];
        $pagos_inv[] = $p;
    }
}
$pagos = array_merge($pagos_prov, $pagos_nom, $pagos_inv);   // para el detalle en el JS (pagosData)

// ============================================================
// TOTALES POR ESTADO (por sección)
// ============================================================
function totales_pagos(array $lista): array {
    $t = ['total' => count($lista), 'APROBADO' => 0, 'PENDIENTE' => 0, 'RECHAZADO' => 0, 'valor' => 0.0];
    foreach ($lista as $p) {
        $e = (string)$p['nom_estado_pago'];
        if (isset($t[$e])) $t[$e]++;
        if ($e === 'APROBADO') $t['valor'] += (float)$p['val_pago'];
    }
    return $t;
}
$tot_prov = totales_pagos($pagos_prov);
$tot_nom  = totales_pagos($pagos_nom);
$tot_inv  = totales_pagos($pagos_inv);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>

<div id="mod-historial" class="app-view active tcx-pantalla" data-lista-fija>

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Historial de pagos</h1>
            <p>Respuesta del banco a los pagos de proveedores, nómina e inversiones. Haga clic en un pago para ver su detalle.</p>
        </div>
        <div class="module-header-acciones">
            <button type="button" id="btn-import-historial" class="btn btn-primary"><i class="fas fa-upload"></i> Importar respuesta del banco</button>
            <input type="file" id="csv-input" accept=".csv,text/csv" hidden>
        </div>
    </div>

    <!-- SECCIONES (la importación sirve para las tres: cada línea se aplica según su archivo plano) -->
    <div class="ap-tabs" role="tablist" aria-label="Tipo de pago">
        <button type="button" class="ap-tab active" role="tab" aria-selected="true" data-tab="proveedores">
            <i class="fas fa-truck"></i> Proveedores
            <span class="ap-tab-count"><?= $tot_prov['total'] ?></span>
        </button>
        <button type="button" class="ap-tab" role="tab" aria-selected="false" data-tab="nomina">
            <i class="fas fa-users"></i> Nómina
            <span class="ap-tab-count"><?= $tot_nom['total'] ?></span>
            <?php if ($tot_nom['RECHAZADO'] > 0): ?>
                <span class="ap-tab-alerta" title="Pagos de nómina que el banco rechazó: Gestión Humana debe corregir la cuenta y reenviarlos"><?= $tot_nom['RECHAZADO'] ?> rechazado<?= $tot_nom['RECHAZADO'] !== 1 ? 's' : '' ?></span>
            <?php endif; ?>
        </button>
        <button type="button" class="ap-tab" role="tab" aria-selected="false" data-tab="inversiones">
            <i class="fas fa-hand-holding-dollar"></i> Inversiones
            <span class="ap-tab-count"><?= $tot_inv['total'] ?></span>
            <?php if ($tot_inv['RECHAZADO'] > 0): ?>
                <span class="ap-tab-alerta" title="Pagos de inversiones que el banco rechazó: Financiero debe corregir la cuenta del inversor y reenviarlos"><?= $tot_inv['RECHAZADO'] ?> rechazado<?= $tot_inv['RECHAZADO'] !== 1 ? 's' : '' ?></span>
            <?php endif; ?>
        </button>
    </div>

    <!-- Indicadores de la sección activa: los calcula pagos_tescxp.js sobre todos sus pagos -->
    <div class="stats-grid">
        <div class="stat-card" style="--i:0">
            <div class="stat-icon blue"><i class="fas fa-receipt" id="stat-total-icono"></i></div>
            <div class="stat-info">
                <div class="stat-label" id="stat-total-label">Total pagos</div>
                <div class="stat-value" id="stat-total">0</div>
                <div class="stat-hint" id="stat-total-hint">Con respuesta registrada</div>
            </div>
        </div>
        <div class="stat-card" style="--i:1">
            <div class="stat-icon green"><i class="fas fa-circle-check"></i></div>
            <div class="stat-info">
                <div class="stat-label">Aprobados</div>
                <div class="stat-value" id="stat-aprobados">0</div>
                <div class="stat-hint" id="stat-aprobados-hint">Descontaron saldo</div>
            </div>
        </div>
        <div class="stat-card" style="--i:2">
            <div class="stat-icon rose"><i class="fas fa-circle-xmark"></i></div>
            <div class="stat-info">
                <div class="stat-label">Rechazados</div>
                <div class="stat-value" id="stat-rechazados">0</div>
                <div class="stat-hint">Se deben corregir y reenviar</div>
            </div>
        </div>
        <div class="stat-card" style="--i:3">
            <div class="stat-icon amber"><i class="fas fa-coins"></i></div>
            <div class="stat-info">
                <div class="stat-label">Valor aprobado</div>
                <div class="stat-value" id="stat-valor">$0</div>
                <div class="stat-hint">Pagado por el banco</div>
            </div>
        </div>
    </div>

    <!-- Filtros (componente "filtros": píldoras con conteo) -->
    <div class="filter-bar">
        <div class="filter-row">
            <div class="search-wrapper">
                <span class="search-icon"><i class="fas fa-search"></i></span>
                <input type="search" id="pago-search" class="search-input" maxlength="80" autocomplete="off" placeholder="Buscar por pago, factura, proveedor o código del banco...">
            </div>
            <div class="filter-toggle-group" role="group" aria-label="Estado" data-para="pago-filtro-estado">
                <button type="button" class="filter-toggle active" data-valor="all" aria-pressed="true">Todos <span class="count" id="pag-cnt-all"></span></button>
                <button type="button" class="filter-toggle" data-valor="APROBADO" aria-pressed="false">Aprobados <span class="count" id="pag-cnt-APROBADO"></span></button>
                <button type="button" class="filter-toggle" data-valor="PENDIENTE" aria-pressed="false">Pendientes <span class="count" id="pag-cnt-PENDIENTE"></span></button>
                <button type="button" class="filter-toggle" data-valor="RECHAZADO" aria-pressed="false">Rechazados <span class="count" id="pag-cnt-RECHAZADO"></span></button>
            </div>
            <input type="hidden" id="pago-filtro-estado" value="all">
            <div class="filter-dates">
                <label for="fec-desde">Desde</label>
                <input type="date" id="fec-desde" class="filter-date-input" aria-label="Fecha de pago desde" title="Desde">
                <label for="fec-hasta">Hasta</label>
                <span class="filter-dates-sep" aria-hidden="true">–</span>
                <input type="date" id="fec-hasta" class="filter-date-input" aria-label="Fecha de pago hasta" title="Hasta">
            </div>
            <button type="button" id="btn-clear-filters" class="btn-clear-filter" hidden><i class="fas fa-eraser"></i> Limpiar</button>
        </div>
        <div class="filter-info" id="pagos-count" aria-live="polite">0 resultados</div>
    </div>

    <!-- Listas (una por sección): las pinta pagos_tescxp.js; clic en la fila abre el detalle -->
    <div class="table-container" data-lista>
        <div data-lista-scroll>
            <table class="data-table" id="tabla-proveedores" data-seccion="proveedores" data-erp-movil data-erp-movil-titulo="2">
                <thead>
                    <tr>
                        <th>Pago</th>
                        <th>Factura / cuota</th>
                        <th>Archivo plano</th>
                        <th>Fecha de pago</th>
                        <th class="text-right">Valor</th>
                        <th>Respuesta del banco</th>
                        <th>Estado</th>
                    </tr>
                </thead>
                <tbody id="tbody-proveedores"></tbody>
            </table>
            <table class="data-table" id="tabla-nomina" data-seccion="nomina" data-erp-movil data-erp-movil-titulo="2" hidden>
                <thead>
                    <tr>
                        <th>Pago</th>
                        <th>Empleado</th>
                        <th>Periodo</th>
                        <th>Archivo plano</th>
                        <th>Fecha de pago</th>
                        <th class="text-right">Valor</th>
                        <th>Respuesta del banco</th>
                        <th>Estado</th>
                    </tr>
                </thead>
                <tbody id="tbody-nomina"></tbody>
            </table>
            <table class="data-table" id="tabla-inversiones" data-seccion="inversiones" data-erp-movil data-erp-movil-titulo="2" hidden>
                <thead>
                    <tr>
                        <th>Pago</th>
                        <th>Inversor</th>
                        <th>Proyecto / cuota</th>
                        <th>Archivo plano</th>
                        <th>Fecha de pago</th>
                        <th class="text-right">Valor</th>
                        <th>Respuesta del banco</th>
                        <th>Estado</th>
                    </tr>
                </thead>
                <tbody id="tbody-inversiones"></tbody>
            </table>
        </div>
    </div>
</div>

<!-- MODAL: IMPORTAR RESPUESTA DEL BANCO -->
<div id="modal-import" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3>Importar respuesta del banco</h3>
                <p id="import-subtitle">Revise las filas antes de aplicarlas</p>
            </div>
            <button type="button" class="modal-close" id="close-import-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="import-form" novalidate>
                <input type="hidden" name="btn_importar" value="1">
                <input type="hidden" name="hid_filas_importar" id="hid-filas-importar" value="">

                <p class="config-hint">
                    <i class="fas fa-info-circle"></i>
                    <span>El archivo debe traer <strong>ID Archivo Plano</strong>, <strong>Consecutivo</strong> (número de línea
                    del pago en el archivo plano), <strong>Estado</strong> (APROBADO o RECHAZADO), <strong>Código Respuesta</strong>
                    y <strong>Fecha Pago</strong>. Se verifica que documento, cuenta y valor coincidan con la línea del archivo plano.
                    Si esa línea ya tiene respuesta, se omite.</span>
                </p>

                <div class="import-resumen" id="import-resumen">
                    <div class="import-resumen-item ok">
                        <span class="import-resumen-label">Por aplicar</span>
                        <span class="import-resumen-valor" id="import-validas">0</span>
                    </div>
                    <div class="import-resumen-item bad">
                        <span class="import-resumen-label">Con errores</span>
                        <span class="import-resumen-valor" id="import-invalidas">0</span>
                    </div>
                    <div class="import-resumen-item">
                        <span class="import-resumen-label">Filas leídas</span>
                        <span class="import-resumen-valor" id="import-total">0</span>
                    </div>
                </div>

                <h4 class="detail-subheading"><i class="fas fa-list-check"></i> Filas del archivo</h4>
                <div id="import-filas-list" class="import-list"></div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary" id="cancel-import-modal">Cancelar</button>
            <button type="button" id="import-btn-apply" class="btn btn-primary" disabled>
                <i class="fas fa-check"></i> Aplicar pagos
            </button>
        </div>
    </div>
</div>

<!-- MODAL: DETALLE DEL PAGO -->
<div id="modal-detail" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3 id="detail-title">Detalle del pago</h3>
                <p id="detail-subtitle">Respuesta del banco para este pago</p>
            </div>
            <button type="button" class="modal-close" id="close-detail-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <div id="detail-content"></div>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary" id="close-detail-btn">Cerrar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="tcx-toast hidden" role="status" aria-live="polite"><span id="toast-message"></span></div>

<script>
// Datos completos para el detalle y los totales filtrados
const pagosData = <?= json_encode($pagos, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG) ?>;
</script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
