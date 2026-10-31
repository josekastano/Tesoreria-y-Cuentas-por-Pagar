<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Archivo Plano";
$page_description = "Generación del archivo plano para pago de cronogramas al banco";
$page_icon        = "bi-file-earmark-spreadsheet";
$page_extra_css   = ["../modules/tescxp/css/archivo_plano.css"];
$page_extra_js    = ["../modules/tescxp/js/archivo_plano.js"];
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// MODELO (resumen)
// ============================================================
// - ENCABEZADO (tab_enc_archivo_plano): cuenta de ORIGEN de la empresa
//   (id_empresa, cta_empresa, y su id_banco e ind_tipocuenta), nom_empresa
//   (de tab_pmtros_grales),
//   fecha_aplicacion, id_tipo_pago. Ya NO lleva cronograma: el banco del
//   archivo es el de la cuenta de origen.
// - DETALLE (tab_det_archivo_plano): una línea por cuota, con su
//   id_cronograma y una COPIA de los datos del beneficiario (tipo y número de
//   documento, nombre, banco, tipo de cuenta y cuenta).
// - Una cuota rechazada por el banco vuelve a quedar disponible para un
//   archivo nuevo (reintento). Lo valida fun_insert_det_archivo_plano.

// ============================================================
// LIMPIAR MENSAJE DE ERROR DE POSTGRESQL
// ============================================================
function limpiar_error_pgsql(string $msg): string {
    if (preg_match('/ERROR:\s*ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    if (preg_match('/ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    return $msg;
}

// ============================================================
// RESPUESTA JSON A PRUEBA DE SALIDA ESPURIA
// ============================================================
// Un warning o notice de PHP impreso antes del JSON hace que JSON.parse falle
// en el front. Todo el bloque POST corre dentro de un buffer: lo que se haya
// impreso de más se descarta y se devuelve en debug_salida_previa.
function responder_json(array $respuesta): void {
    $basura = '';
    while (ob_get_level() > 0) {
        $basura = ((string)ob_get_clean()) . $basura;
    }

    $basura = trim(strip_tags($basura));
    if ($basura !== '' && preg_match('/(fatal|error|warning|notice|deprecated|exception)/i', $basura)) {
        $respuesta['debug_salida_previa'] = substr($basura, 0, 800);
    }

    $json = json_encode($respuesta, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
    if ($json === false) {
        $json = json_encode([
            'success' => false,
            'message' => 'No se pudo serializar la respuesta: ' . json_last_error_msg(),
            'errors'  => [],
        ]);
    }

    echo $json;
    exit;
}

// ============================================================
// RESPUESTA CSV PARA DESCARGA DE ARCHIVOS
// ============================================================
// El CSV se arma primero en memoria; así ningún warning de PHP termina metido
// entre las filas del archivo que se sube al banco. $escape se pasa explícito
// porque PHP 8.4 marcó como deprecated no pasarlo.
function responder_csv(string $nombre_archivo, array $filas): void {
    $mem = fopen('php://temp', 'w+');
    foreach ($filas as $fila) {
        fputcsv($mem, $fila, ';', '"', '\\');
    }
    rewind($mem);
    $contenido_csv = stream_get_contents($mem);
    fclose($mem);

    while (ob_get_level() > 0) {
        ob_end_clean();
    }

    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . $nombre_archivo . '.csv"');
    header('Cache-Control: no-cache, must-revalidate');
    header('Pragma: public');

    // BOM UTF-8: sin esto Excel en Windows muestra mal tildes y "ñ".
    echo "\xEF\xBB\xBF" . $contenido_csv;
    exit;
}

// Evita el "Call to a member function execute() on null" cuando una consulta
// preparada no existe en prepare_tescxp.php: lanza una excepción con el nombre.
function requerir_stmt($stmt, string $nombre): PDOStatement {
    if (!($stmt instanceof PDOStatement)) {
        throw new Exception('La consulta preparada $' . $nombre . ' no está definida en prepare_tescxp.php.');
    }
    return $stmt;
}

// PostgreSQL devuelve los booleanos vía PDO como 't' / 'f' (o true/false).
function es_verdadero($valor): bool {
    return in_array($valor, ['t', 'T', 'true', 'TRUE', '1', 1, true], true);
}

// Booleano listo para mandarlo a PostgreSQL por PDO
function pg_bool($valor): string {
    return es_verdadero($valor) ? 'true' : 'false';
}

// Excel convierte los números largos (cuentas, NIT, documentos) a notación
// científica (1,23457E+15) y les pierde dígitos. Escribirlos como ="123..."
// hace que Excel los trate como texto y los muestre completos.
function texto_excel($valor): string {
    $v = trim((string)$valor);
    return preg_match('/^\d+$/', $v) ? '="' . $v . '"' : $v;
}

function tipo_cuenta_txt($valor): string {
    return es_verdadero($valor) ? 'Corriente' : 'Ahorros';
}


// ============================================================
// CUOTAS DISPONIBLES Y CUENTAS DE UN CRONOGRAMA, POR PROVEEDOR
// ============================================================
// $list_cuotas_de_cronograma trae solo las cuotas que todavía pueden ir a un
// archivo: sin pagar y que no estén en otro archivo vigente (las rechazadas
// vuelven a salir, marcadas con es_reintento). $list_ctas_prov_de_cronograma
// trae las cuentas activas de cada proveedor; el cruce se hace aquí.
function cargar_proveedores_cronograma(int $id_cronograma, $stmt_cuotas, $stmt_ctas): array {
    $stmt_cuotas = requerir_stmt($stmt_cuotas, 'list_cuotas_de_cronograma');
    $stmt_ctas   = requerir_stmt($stmt_ctas,   'list_ctas_prov_de_cronograma');

    $stmt_cuotas->execute([':wid_cronograma' => $id_cronograma]);
    $cuotas = $stmt_cuotas->fetchAll(PDO::FETCH_ASSOC);

    $stmt_ctas->execute([':wid_cronograma' => $id_cronograma]);
    $cuentas = $stmt_ctas->fetchAll(PDO::FETCH_ASSOC);

    $ctas_por_prov = [];
    foreach ($cuentas as $c) {
        $ctas_por_prov[(string)$c['id_proveedor']][] = [
            'cta_proveedor'  => $c['cta_proveedor'],
            'id_banco'       => $c['id_banco'],
            'nom_banco'      => $c['nom_banco'],
            'ind_tipocuenta' => es_verdadero($c['ind_tipocuenta']),
        ];
    }

    $proveedores = [];
    foreach ($cuotas as $q) {
        $idp = (string)$q['id_proveedor'];
        if (!isset($proveedores[$idp])) {
            $proveedores[$idp] = [
                'id_proveedor' => $q['id_proveedor'],
                'id_tipo'      => $q['id_tipo'],      // NIT, CC... (tab_terceros)
                'nom_tercero'  => $q['nom_tercero'],
                'cuentas'      => $ctas_por_prov[$idp] ?? [],
                'cuotas'       => [],
                'total'        => 0.0,
            ];
        }
        $proveedores[$idp]['cuotas'][] = [
            'id_cronograma' => (int)$q['id_cronograma'],
            'id_factura'    => (int)$q['id_factura'],
            'id_cuota'      => (int)$q['id_cuota'],
            'val_a_pagar'   => (float)$q['val_a_pagar'],
            'es_reintento'  => es_verdadero($q['es_reintento'] ?? false),
        ];
        $proveedores[$idp]['total'] += (float)$q['val_a_pagar'];
    }

    return array_values($proveedores);
}

// ============================================================
// CARGAR SELECTS (siempre se cargan para la vista inicial)
// ============================================================
$list_ctas_empresa->execute();
$ctas_empresa_disp = $list_ctas_empresa->fetchAll(PDO::FETCH_ASSOC);

$list_cronogramas_pendientes->execute();
$cronogramas_pend = $list_cronogramas_pendientes->fetchAll(PDO::FETCH_ASSOC);

$list_tipos_pago->execute();
$tipos_pago = $list_tipos_pago->fetchAll(PDO::FETCH_ASSOC);

// Días de pago de Parámetros de Tesorería (1 = lunes ... 6 = sábado)
$list_pmtros_tescxp->execute();
$pmtros   = $list_pmtros_tescxp->fetch(PDO::FETCH_ASSOC) ?: null;
$dias_pago = $pmtros
    ? array_values(array_unique(array_map('intval', [$pmtros['fec_diapago1'], $pmtros['fec_diapago2'], $pmtros['fec_diapago3']])))
    : [];

// Festivos activos: 'YYYY-MM-DD' => nombre
$list_festivos->execute();
$festivos = [];
foreach ($list_festivos->fetchAll(PDO::FETCH_ASSOC) as $f) {
    $festivos[date('Y-m-d', strtotime($f['fecha']))] = $f['nom_festivo'];
}

// ¿La fecha es día de pago y no es festivo? Devuelve el motivo si no se puede.
function motivo_fecha_no_valida(string $fecha, array $dias_pago, array $festivos): ?string {
    if (empty($dias_pago)) {
        return 'No hay días de pago configurados en Parámetros de Tesorería.';
    }
    $dia = (int)date('N', strtotime($fecha)); // 1 = lunes ... 7 = domingo
    if (!in_array($dia, $dias_pago, true)) {
        return 'La fecha de aplicación debe caer en un día de pago (' . nombres_dias($dias_pago) . ').';
    }
    if (isset($festivos[$fecha])) {
        return 'La fecha de aplicación es festivo (' . $festivos[$fecha] . ').';
    }
    return null;
}

function nombres_dias(array $dias): string {
    $nombres = [1 => 'lunes', 2 => 'martes', 3 => 'miércoles', 4 => 'jueves', 5 => 'viernes', 6 => 'sábado', 7 => 'domingo'];
    sort($dias);
    return implode(', ', array_map(fn($d) => $nombres[$d] ?? $d, $dias));
}

// Primera fecha válida desde hoy (para precargar el formulario)
function proxima_fecha_valida(array $dias_pago, array $festivos): string {
    $fecha = new DateTime('today');
    for ($i = 0; $i < 120; $i++) {
        $iso = $fecha->format('Y-m-d');
        if (motivo_fecha_no_valida($iso, $dias_pago, $festivos) === null) {
            return $iso;
        }
        $fecha->modify('+1 day');
    }
    return '';
}

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON, SALVO LA DESCARGA)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    ob_start();
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- CUOTAS + CUENTAS DE UN CRONOGRAMA (para armar el form dinámico) ----------
        if (isset($_POST['btn_cargar_crono'])) {
            $id_cronograma = (int)($_POST['hid_id_cronograma'] ?? 0);
            if ($id_cronograma <= 0) {
                throw new Exception('Cronograma no válido.');
            }

            $respuesta['success']     = true;
            $respuesta['proveedores'] = cargar_proveedores_cronograma(
                $id_cronograma,
                $list_cuotas_de_cronograma    ?? null,
                $list_ctas_prov_de_cronograma ?? null
            );
            responder_json($respuesta);
        }

        // ---------- DETALLE DE UN ARCHIVO PLANO (con la respuesta del banco por línea) ----------
        if (isset($_POST['btn_ver_detalle'])) {
            $id_archivo_plano = (int)($_POST['hid_id_archivo_plano'] ?? 0);
            if ($id_archivo_plano <= 0) {
                throw new Exception('Archivo plano no válido.');
            }

            $stmt_det = requerir_stmt($list_det_archivo_plano ?? null, 'list_det_archivo_plano');
            $stmt_det->execute([':wid_archivo_plano' => $id_archivo_plano]);
            $detalle = $stmt_det->fetchAll(PDO::FETCH_ASSOC);

            // Estado del pago de cada línea (sin respuesta / pendiente / aprobado / rechazado)
            $stmt_con = requerir_stmt($list_conciliacion_archivo ?? null, 'list_conciliacion_archivo');
            $stmt_con->execute([':wid_archivo_plano' => $id_archivo_plano]);
            $estados = [];
            foreach ($stmt_con->fetchAll(PDO::FETCH_ASSOC) as $c) {
                $estados[$c['id_factura'] . '-' . $c['id_cuota']] = $c;
            }

            foreach ($detalle as &$d) {
                $c = $estados[$d['id_factura'] . '-' . $d['id_cuota']] ?? null;
                $d['tipo_cuenta']     = tipo_cuenta_txt($d['ind_tipocuenta']);
                $d['estado_pago']     = $c['estado_pago']     ?? null;
                $d['nom_estado_pago'] = $c['nom_estado_pago'] ?? null;
                $d['id_codigo']       = $c['id_codigo']       ?? null;
                $d['des_motivo']      = $c['des_motivo']      ?? null;
            }
            unset($d);

            $respuesta['success'] = true;
            $respuesta['detalle'] = $detalle;
            responder_json($respuesta);
        }

        // ---------- DESCARGAR ARCHIVO PLANO (CSV) ----------
        // Si algo falla, la excepción viaja como JSON; el front distingue
        // error (JSON) de éxito (CSV) por el Content-Type.
        if (isset($_POST['btn_descargar_archivo_plano'])) {
            $id_archivo_plano = (int)($_POST['hid_id_archivo_plano'] ?? 0);
            if ($id_archivo_plano <= 0) {
                throw new Exception('Archivo plano no válido.');
            }

            $stmt_enc = requerir_stmt($get_enc_archivo_plano ?? null, 'get_enc_archivo_plano');
            $stmt_enc->execute([':wid_archivo_plano' => $id_archivo_plano]);
            $enc = $stmt_enc->fetch(PDO::FETCH_ASSOC);
            if (!$enc) {
                throw new Exception('El archivo plano solicitado no existe.');
            }

            $stmt_det = requerir_stmt($list_det_archivo_plano ?? null, 'list_det_archivo_plano');
            $stmt_det->execute([':wid_archivo_plano' => $id_archivo_plano]);
            $detalle = $stmt_det->fetchAll(PDO::FETCH_ASSOC);
            if (empty($detalle)) {
                throw new Exception('Este archivo plano no tiene pagos para descargar.');
            }

            // La primera descarga lo marca como generado (fec_generacion la pone
            // trg_fecha_generacion_archivo). Volver a descargarlo no cambia nada.
            requerir_stmt($upd_generar_archivo_plano ?? null, 'upd_generar_archivo_plano')
                ->execute([':wid_archivo_plano' => $id_archivo_plano]);

            // Formato: una línea con el nombre de las columnas y después una línea
            // por pago (sin registros ENC/DET), con los datos en este orden:
            //   1. NIT de la empresa                 7. Número de documento (proveedor)
            //   2. Nombre de la empresa              8. Nombre del proveedor
            //   3. NIT del banco de origen           9. NIT del banco de destino
            //   4. Tipo de cuenta origen (empresa)  10. Tipo de cuenta destino (proveedor)
            //   5. Número de cuenta origen          11. Número de cuenta destino
            //   6. Tipo de documento (proveedor)    12. Valor a pagar
            // Los datos de origen salen del encabezado guardado y los del proveedor
            // de la copia en el detalle, así el archivo refleja exactamente lo que
            // quedó registrado (trazabilidad). El banco se identifica por id_banco.
            // id_factura e id_cuota no van: al banco no le sirven, son de control interno.
            // Primera línea: el nombre de cada columna
            $filas = [[
                'NIT Empresa',
                'Nombre Empresa',
                'NIT Banco Origen',
                'Tipo Cuenta Origen',
                'Cuenta Origen',
                'Tipo Documento Proveedor',
                'Documento Proveedor',
                'Nombre Proveedor',
                'NIT Banco Destino',
                'Tipo Cuenta Destino',
                'Cuenta Destino',
                'Valor a Pagar',
            ]];
            foreach ($detalle as $d) {
                $filas[] = [
                    texto_excel($enc['id_empresa']),             // 1
                    $enc['nom_empresa'],                         // 2
                    texto_excel($enc['id_banco']),               // 3
                    tipo_cuenta_txt($enc['ind_tipocuenta']),     // 4
                    texto_excel($enc['cta_empresa']),            // 5
                    $d['id_tipo'],                               // 6
                    texto_excel($d['id_proveedor']),             // 7
                    $d['nom_tercero'],                           // 8
                    texto_excel($d['id_banco']),                 // 9
                    tipo_cuenta_txt($d['ind_tipocuenta']),       // 10
                    texto_excel($d['cta_proveedor']),            // 11
                    number_format((float)$d['val_a_pagar'], 0, '', ''),  // 12 (pesos, sin separadores)
                ];
            }

            $nombre_archivo = preg_replace('/[^A-Za-z0-9_\-]/', '_', (string)$enc['nom_archivo']);
            if ($nombre_archivo === '') {
                $nombre_archivo = 'archivo_plano_' . $id_archivo_plano;
            }

            responder_csv($nombre_archivo, $filas);
        }

        // ---------- NUEVO ARCHIVO PLANO ----------
        if (isset($_POST['btn_nuevo'])) {
            $id_cronograma     = (int)($_POST['sel_id_cronograma']    ?? 0);
            $cta_empresa_combo = trim($_POST['sel_cta_empresa']       ?? '');
            $id_tipo_pago      = (int)($_POST['sel_id_tipo_pago']     ?? 0);
            $nom_archivo       = trim($_POST['txt_nom_archivo']       ?? '');
            $fecha_aplicacion  = trim($_POST['dat_fecha_aplicacion']  ?? '');
            $concepto          = trim($_POST['txt_concepto']          ?? '');
            // Por proveedor, la cuenta elegida en JSON: {"id_proveedor": {"cta": "..."}}.
            // Las cuotas y el tipo de documento no viajan por el formulario: se
            // leen en el servidor (cronograma y tab_terceros).
            $elegidos = json_decode($_POST['hid_ctas_proveedor'] ?? '', true);
            if (!is_array($elegidos)) {
                $elegidos = [];
            }

            $errores = [];

            if ($id_cronograma <= 0) {
                $errores['err-new-cronograma'] = 'Seleccione un cronograma.';
            }
            if (strlen($nom_archivo) < 3 || strlen($nom_archivo) > 30) {
                $errores['err-new-nombre'] = 'El nombre debe tener entre 3 y 30 caracteres.';
            }
            if ($id_tipo_pago <= 0) {
                $errores['err-new-tipo-pago'] = 'Seleccione el tipo de pago.';
            }
            $fecha_ok = DateTime::createFromFormat('Y-m-d', $fecha_aplicacion);
            if (!$fecha_ok || $fecha_ok->format('Y-m-d') !== $fecha_aplicacion) {
                $errores['err-new-fecha'] = 'Indique la fecha de aplicación.';
            } elseif ($fecha_aplicacion < date('Y-m-d')) {
                $errores['err-new-fecha'] = 'La fecha de aplicación no puede ser anterior a hoy.';
            } elseif (($motivo = motivo_fecha_no_valida($fecha_aplicacion, $dias_pago, $festivos)) !== null) {
                $errores['err-new-fecha'] = $motivo;
            }
            if (strlen($concepto) > 80) {
                $errores['err-new-concepto'] = 'El concepto no puede superar 80 caracteres.';
            }

            // Cuenta de origen: "id_empresa:cta_empresa". El banco y el tipo de
            // cuenta del encabezado salen de esa cuenta, no del formulario.
            $cta_origen = null;
            if (strpos($cta_empresa_combo, ':') !== false) {
                [$id_empresa, $cta_empresa] = explode(':', $cta_empresa_combo, 2);
                foreach ($ctas_empresa_disp as $ce) {
                    if ((string)$ce['id_empresa'] === $id_empresa && (string)$ce['cta_empresa'] === $cta_empresa) {
                        $cta_origen = $ce;
                        break;
                    }
                }
            }
            if ($cta_origen === null) {
                $errores['err-new-cuenta-empresa'] = 'Seleccione la cuenta de la empresa de origen.';
            }
            // El nombre de la empresa no se digita: sale de tab_pmtros_grales
            // (viene en $list_ctas_empresa junto con la cuenta).
            $nom_empresa = $cta_origen ? trim((string)$cta_origen['nom_empresa']) : '';

            // ---------------------------------------------------------------
            // ARMAR EL DETALLE EN EL SERVIDOR
            // ---------------------------------------------------------------
            // Una fila por cuota disponible del cronograma. La cuenta del
            // proveedor es la elegida (validada contra sus cuentas activas) o
            // la primera activa; banco y tipo de cuenta salen de la base.
            $filas      = [];
            $sin_cuenta = [];

            if ($id_cronograma > 0) {
                $proveedores = cargar_proveedores_cronograma(
                    $id_cronograma,
                    $list_cuotas_de_cronograma    ?? null,
                    $list_ctas_prov_de_cronograma ?? null
                );

                foreach ($proveedores as $prov) {
                    if (empty($prov['cuentas'])) {
                        $sin_cuenta[] = $prov['nom_tercero'];
                        continue;
                    }

                    $idp      = (string)$prov['id_proveedor'];
                    $eleccion = $elegidos[$idp] ?? [];

                    $cuenta = $prov['cuentas'][0];
                    foreach ($prov['cuentas'] as $c) {
                        if ((string)$c['cta_proveedor'] === (string)($eleccion['cta'] ?? '')) {
                            $cuenta = $c;
                            break;
                        }
                    }

                    // Tipo de documento del proveedor, tal como está en tab_terceros
                    $tipo_doc = strtoupper(trim((string)$prov['id_tipo']));

                    // nom_tercero en el detalle admite 4..50 caracteres
                    $nom_tercero = substr(trim((string)$prov['nom_tercero']), 0, 50);

                    foreach ($prov['cuotas'] as $q) {
                        $filas[] = [
                            'id_cronograma'  => $q['id_cronograma'],
                            'id_factura'     => $q['id_factura'],
                            'id_cuota'       => $q['id_cuota'],
                            'id_tipo'        => $tipo_doc,
                            'id_proveedor'   => $prov['id_proveedor'],
                            'nom_tercero'    => $nom_tercero,
                            'id_banco'       => $cuenta['id_banco'],
                            'ind_tipocuenta' => $cuenta['ind_tipocuenta'],
                            'cta_proveedor'  => $cuenta['cta_proveedor'],
                            // Concepto: el del formulario, o uno por línea si se dejó vacío
                            'concepto'       => $concepto !== ''
                                ? $concepto
                                : 'Pago factura ' . $q['id_factura'] . ' cuota ' . $q['id_cuota'],
                        ];
                    }
                }

                if (!empty($sin_cuenta)) {
                    $errores['err-new-cronograma'] = 'Sin cuenta bancaria activa: ' . implode(', ', $sin_cuenta)
                        . '. Regístrela en Bancos por Proveedor antes de generar el archivo.';
                } elseif (empty($filas)) {
                    $errores['err-new-cronograma'] = 'El cronograma no tiene cuotas disponibles: ya están pagadas o en otro archivo plano sin rechazar.';
                }
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                responder_json($respuesta);
            }

            $stmt_ins_enc = requerir_stmt($ins_enc_archivo_plano ?? null, 'ins_enc_archivo_plano');
            $stmt_ins_det = requerir_stmt($ins_det_archivo_plano ?? null, 'ins_det_archivo_plano');
            $stmt_id      = requerir_stmt($get_id_archivo_recien_creado ?? null, 'get_id_archivo_recien_creado');

            $pdo->beginTransaction();

            $stmt_ins_enc->execute([
                ':wnom_archivo'      => $nom_archivo,
                ':wid_empresa'       => $cta_origen['id_empresa'],
                ':wnom_empresa'      => $nom_empresa,
                ':wid_banco'         => $cta_origen['id_banco'],
                ':wind_tipocuenta'   => pg_bool($cta_origen['ind_tipocuenta']),
                ':wcta_empresa'      => $cta_origen['cta_empresa'],
                ':wfecha_aplicacion' => $fecha_aplicacion,
                ':wid_tipo_pago'     => $id_tipo_pago,
            ]);

            $stmt_id->execute([
                ':wnom_archivo' => $nom_archivo,
                ':wid_empresa'  => $cta_origen['id_empresa'],
                ':wcta_empresa' => $cta_origen['cta_empresa'],
            ]);
            $id_nuevo = (int)$stmt_id->fetchColumn();
            if ($id_nuevo <= 0) {
                throw new Exception('No se pudo recuperar el encabezado del archivo plano recién creado.');
            }

            foreach ($filas as $fila) {
                $stmt_ins_det->execute([
                    ':wid_archivo_plano' => $id_nuevo,
                    ':wid_cronograma'    => $fila['id_cronograma'],
                    ':wid_factura'       => $fila['id_factura'],
                    ':wid_cuota'         => $fila['id_cuota'],
                    ':wid_tipo'          => $fila['id_tipo'],
                    ':wid_proveedor'     => $fila['id_proveedor'],
                    ':wnom_tercero'      => $fila['nom_tercero'],
                    ':wid_banco'         => $fila['id_banco'],
                    ':wind_tipocuenta'   => pg_bool($fila['ind_tipocuenta']),
                    ':wcta_proveedor'    => $fila['cta_proveedor'],
                    ':wconcepto'         => substr($fila['concepto'], 0, 80),
                ]);
            }

            $pdo->commit();

            $respuesta['success'] = true;
            $respuesta['message'] = 'Archivo plano creado con ' . count($filas) . ' pago(s). Descárguelo para enviarlo al banco.';
            responder_json($respuesta);
        }

        // ---------- EDITAR ARCHIVO PLANO (solo el nombre) ----------
        // El banco del encabezado es el de la cuenta de origen: no se cambia
        // aquí (se reenvía el mismo) para que no deje de coincidir con la cuenta.
        if (isset($_POST['btn_editar'])) {
            $id_archivo_plano = (int)($_POST['hid_edit_id']          ?? 0);
            $nom_archivo      = trim($_POST['txt_edit_nom_archivo']  ?? '');

            if ($id_archivo_plano <= 0) {
                throw new Exception('Archivo plano no válido.');
            }
            if (strlen($nom_archivo) < 3 || strlen($nom_archivo) > 30) {
                $respuesta['errors'] = ['err-edit-nombre' => 'El nombre debe tener entre 3 y 30 caracteres.'];
                responder_json($respuesta);
            }

            $stmt_enc = requerir_stmt($get_enc_archivo_plano ?? null, 'get_enc_archivo_plano');
            $stmt_enc->execute([':wid_archivo_plano' => $id_archivo_plano]);
            $enc = $stmt_enc->fetch(PDO::FETCH_ASSOC);
            if (!$enc) {
                throw new Exception('El archivo plano no existe.');
            }
            if (es_verdadero($enc['ind_generado'])) {
                throw new Exception('El archivo plano ya fue generado y no se puede editar.');
            }

            requerir_stmt($upd_enc_archivo_plano ?? null, 'upd_enc_archivo_plano')->execute([
                ':wid_archivo_plano' => $id_archivo_plano,
                ':wid_banco'         => $enc['id_banco'],
                ':wnom_archivo'      => $nom_archivo,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Archivo plano actualizado correctamente.';
            responder_json($respuesta);
        }

        $respuesta['message'] = 'Acción no válida.';
        responder_json($respuesta);

    } catch (Throwable $e) {
        // Throwable: un TypeError o Error de PHP también debe salir como JSON
        if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
            $pdo->rollBack();
        }
        $mensaje = limpiar_error_pgsql($e->getMessage());
        if (empty($mensaje)) {
            $mensaje = $e->getMessage();
        }
        $respuesta['message']      = $mensaje;
        $respuesta['debug_origen'] = basename($e->getFile()) . ':' . $e->getLine();
        responder_json($respuesta);
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_enc_archivo_plano->execute();
$archivos = $list_enc_archivo_plano->fetchAll(PDO::FETCH_ASSOC);

$hoy = date('Y-m-d');
$fecha_sugerida = proxima_fecha_valida($dias_pago, $festivos);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
<link rel="stylesheet" href="modules/tescxp/css/archivo_plano.css">
<div id="mod-archivo-plano" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Archivo Plano</h1>
            <p>Genere el archivo de pagos para enviar al banco a partir de un cronograma</p>
        </div>
        <button id="btn-add-archivo" class="btn btn-primary">
            <i class="fas fa-plus"></i> Nuevo Archivo Plano
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <?php
        $total      = count($archivos);
        $generados  = count(array_filter($archivos, fn($a) => es_verdadero($a['ind_generado'])));
        $pendientes = $total - $generados;
        ?>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-file-invoice"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total archivos</div>
                <div class="stat-value" id="stat-total"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
            <div class="stat-info">
                <div class="stat-label">Generados</div>
                <div class="stat-value" id="stat-generados"><?= $generados ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-clock"></i></div>
            <div class="stat-info">
                <div class="stat-label">Por generar</div>
                <div class="stat-value" id="stat-pendientes"><?= $pendientes ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="archivo-search" class="search-input" placeholder="Buscar por nombre, banco o cuenta...">
        </div>
        <div class="filter-toggle-group">
            <button class="filter-toggle active" data-filter="all">Todos</button>
            <button class="filter-toggle" data-filter="generado">Generados</button>
            <button class="filter-toggle" data-filter="pendiente">Por generar</button>
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="archivos-page-size">Filas por página</label>
            <select id="archivos-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="archivos-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="archivos-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-archivo">
                <col class="col-origen">
                <col class="col-tipo-pago">
                <col class="col-aplicacion">
                <col class="col-generacion">
                <col class="col-estado">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="text">Archivo <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="text">Cuenta de Origen <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="2" data-sort-type="text">Tipo de Pago <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="3" data-sort-type="text">Aplicación <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="4" data-sort-type="text">Generación <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Estado</th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="archivos-tbody">
            <?php if (empty($archivos)): ?>
                <tr class="empty-row">
                    <td colspan="7">
                        <div class="empty-state">
                            <i class="fas fa-file-invoice"></i>
                            <p>No hay archivos planos</p>
                            <span>Haga clic en "Nuevo Archivo Plano" para crear el primero</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($archivos as $a):
                    $generado  = es_verdadero($a['ind_generado']);
                    $filtro    = $generado ? 'generado' : 'pendiente';
                    $fecha_gen = $a['fec_generacion'] ? date('d/m/Y', strtotime($a['fec_generacion'])) : '—';
                    $fecha_apl = $a['fecha_aplicacion'] ? date('d/m/Y', strtotime($a['fecha_aplicacion'])) : '—';
                    $datos = [
                        'id_archivo_plano' => $a['id_archivo_plano'],
                        'nom_archivo'      => $a['nom_archivo'],
                        'id_empresa'       => $a['id_empresa'],
                        'nom_empresa'      => $a['nom_empresa'],
                        'cta_empresa'      => $a['cta_empresa'],
                        'nom_banco'        => $a['nom_banco'],
                        'tipo_cuenta'      => tipo_cuenta_txt($a['ind_tipocuenta']),
                        'nom_tipo_pago'    => $a['nom_tipo_pago'],
                        'fecha_aplicacion' => $a['fecha_aplicacion'],
                        'fec_generacion'   => $a['fec_generacion'],
                        'generado'         => $generado,
                    ];
                    $json = htmlspecialchars(json_encode($datos, JSON_UNESCAPED_UNICODE), ENT_QUOTES);
                ?>
                <tr data-estado="<?= $filtro ?>" data-archivo="<?= $json ?>">
                    <td data-sort="<?= htmlspecialchars($a['nom_archivo']) ?>">
                        <strong><?= htmlspecialchars($a['nom_archivo']) ?></strong><br>
                        <small class="cell-sub">#<?= htmlspecialchars($a['id_archivo_plano']) ?></small>
                    </td>
                    <td data-sort="<?= htmlspecialchars($a['nom_banco'] . ' ' . $a['cta_empresa']) ?>">
                        <?= htmlspecialchars($a['nom_banco']) ?><br>
                        <small class="cell-sub"><?= htmlspecialchars($a['cta_empresa']) ?> · <?= tipo_cuenta_txt($a['ind_tipocuenta']) ?></small>
                    </td>
                    <td data-sort="<?= htmlspecialchars($a['nom_tipo_pago']) ?>"><?= htmlspecialchars($a['nom_tipo_pago']) ?></td>
                    <td data-sort="<?= htmlspecialchars((string)$a['fecha_aplicacion']) ?>"><?= htmlspecialchars($fecha_apl) ?></td>
                    <td data-sort="<?= htmlspecialchars((string)$a['fec_generacion']) ?>"><?= htmlspecialchars($fecha_gen) ?></td>
                    <td class="text-center">
                        <?php if ($generado): ?>
                            <span class="badge badge-active">Generado</span>
                        <?php else: ?>
                            <span class="badge badge-pending">Por generar</span>
                        <?php endif; ?>
                    </td>
                    <td class="text-center">
                        <button class="btn-icon-sm view" data-action="descargar" title="Descargar CSV">
                            <i class="fas fa-download"></i>
                        </button>
                        <?php if (!$generado): ?>
                            <!-- Solo se edita mientras el archivo no se haya generado -->
                            <button class="btn-icon-sm edit" data-action="editar" title="Editar nombre">
                                <i class="fas fa-edit"></i>
                            </button>
                        <?php else: ?>
                            <span class="accion-bloqueada" title="Archivo generado: no se puede editar">
                                <i class="fas fa-lock"></i>
                            </span>
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            <?php endif; ?>
            </tbody>
        </table>
      </div>

        <!-- PAGINACIÓN -->
        <div class="table-footer">
            <div class="pagination-nav">
                <span class="pagination-range" id="archivos-range">0 de 0</span>
                <button type="button" id="archivos-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="archivos-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVO ARCHIVO PLANO -->
<!-- Dos columnas (datos del archivo | pagos a incluir) para que el modal quepa
     en pantalla sin scroll. La lista de proveedores tiene su propio scroll. -->
<div id="modal-new-archivo" class="modal-overlay hidden">
    <div class="modal-box modal-box-xl">
        <div class="modal-header green">
            <div>
                <h2>Nuevo Archivo Plano</h2>
                <p>Arme el archivo de pagos a partir de un cronograma</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-archivo-form" class="ap-layout" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <input type="hidden" name="hid_ctas_proveedor" id="hid-ctas-proveedor" value="">

                <!-- COLUMNA IZQUIERDA: DATOS DEL ARCHIVO -->
                <div class="ap-col">
                    <div class="form-field">
                        <label class="form-label">Cuenta de Origen (Empresa) <span class="required">*</span></label>
                        <select id="new-cta-empresa" name="sel_cta_empresa" class="form-select" title="El archivo se envía al banco de esta cuenta, y de ella sale el dinero">
                            <option value="">Seleccione...</option>
                            <?php foreach ($ctas_empresa_disp as $ce): ?>
                                <option value="<?= htmlspecialchars($ce['id_empresa']) ?>:<?= htmlspecialchars($ce['cta_empresa']) ?>"
                                        data-empresa="<?= htmlspecialchars($ce['nom_empresa'] . ' · ' . $ce['id_empresa']) ?>">
                                    <?= htmlspecialchars($ce['nom_banco']) ?> — <?= htmlspecialchars($ce['cta_empresa']) ?> (<?= tipo_cuenta_txt($ce['ind_tipocuenta']) ?>)
                                </option>
                            <?php endforeach; ?>
                        </select>
                        <span class="ap-empresa" id="new-empresa-info"></span>
                        <span class="field-error" id="err-new-cuenta-empresa"></span>
                    </div>


                    <div class="form-grid">
                        <div class="form-field">
                            <label class="form-label">Tipo de Pago <span class="required">*</span></label>
                            <select id="new-id-tipo-pago" name="sel_id_tipo_pago" class="form-select">
                                <option value="">Seleccione...</option>
                                <?php foreach ($tipos_pago as $tp): ?>
                                    <option value="<?= htmlspecialchars($tp['id_tipo_pago']) ?>"><?= htmlspecialchars($tp['nom_tipo_pago']) ?></option>
                                <?php endforeach; ?>
                            </select>
                            <span class="field-error" id="err-new-tipo-pago"></span>
                        </div>
                        <div class="form-field">
                            <label class="form-label">Fecha de Aplicación <span class="required">*</span></label>
                            <input type="hidden" id="new-fecha-aplicacion" name="dat_fecha_aplicacion" value="<?= $fecha_sugerida ?>" data-sugerida="<?= $fecha_sugerida ?>">
                            <button type="button" class="form-input dp-trigger" id="new-fecha-aplicacion-btn"
                                    data-target="new-fecha-aplicacion" data-min="<?= $hoy ?>" data-formato="corto"
                                    title="Solo <?= $dias_pago ? htmlspecialchars(nombres_dias($dias_pago)) : 'días de pago' ?> que no sean festivo">
                                <span class="dp-trigger-texto vacio">Seleccione una fecha</span>
                                <i class="fas fa-calendar-alt"></i>
                            </button>
                            <span class="field-error" id="err-new-fecha"></span>
                        </div>
                    </div>

                    <div class="form-grid">
                        <div class="form-field">
                            <label class="form-label">Nombre del Archivo <span class="required">*</span></label>
                            <input type="text" id="new-nom-archivo" name="txt_nom_archivo" class="form-input" placeholder="Ej: pagos_julio" minlength="3" maxlength="30">
                            <span class="field-error" id="err-new-nombre"></span>
                        </div>
                        <div class="form-field">
                            <label class="form-label">Concepto</label>
                            <input type="text" id="new-concepto" name="txt_concepto" class="form-input" placeholder="Opcional" maxlength="80"
                                   title='Si se deja vacío, cada pago lleva "Pago factura N cuota N"'>
                            <span class="field-error" id="err-new-concepto"></span>
                        </div>
                    </div>
                </div>

                <!-- COLUMNA DERECHA: PAGOS A INCLUIR -->
                <div class="ap-col ap-col-pagos">
                    <div class="form-field">
                        <label class="form-label">Cronograma Pendiente <span class="required">*</span></label>
                        <select id="new-id-cronograma" class="form-select" name="sel_id_cronograma">
                            <option value="">Seleccione...</option>
                            <?php foreach ($cronogramas_pend as $cr): ?>
                                <option value="<?= htmlspecialchars($cr['id_cronograma']) ?>">
                                    <?= htmlspecialchars($cr['nom_cronograma']) ?> — <?= htmlspecialchars(date('d/m/Y', strtotime($cr['fec_programacion']))) ?> — $<?= number_format((float)$cr['total_a_pagar'], 0, ',', '.') ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                        <span class="field-error" id="err-new-cronograma"></span>
                    </div>

                    <p class="config-hint" id="prov-cuentas-hint">Seleccione un cronograma para ver los proveedores a pagar.</p>
                    <div id="prov-cuentas-list" class="cuota-picker-list" style="display:none"></div>
                    <div id="prov-cuentas-total" class="picker-total" style="display:none"></div>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <p class="field-hint ap-nota">
                <i class="fas fa-info-circle"></i>
                Fecha: solo <?= $dias_pago ? htmlspecialchars(nombres_dias($dias_pago)) : 'días de pago' ?> que no sean festivo.
                Sin concepto, cada pago lleva "Pago factura N cuota N".
            </p>
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Crear Archivo Plano</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR ARCHIVO PLANO -->
<div id="modal-edit-archivo" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header blue">
            <div>
                <h2>Editar Archivo Plano</h2>
                <p>Solo se puede cambiar el nombre mientras no se haya generado</p>
            </div>
            <button class="modal-close btn-close-edit-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-archivo-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id" id="edit-archivo-id" value="">
                <div class="form-field">
                    <label class="form-label">Cuenta de Origen</label>
                    <input type="text" id="edit-origen-display" class="form-input" disabled="disabled">
                    <p class="field-hint">Para usar otra cuenta de origen, cree un archivo nuevo.</p>
                </div>
                <div class="form-field">
                    <label class="form-label">Nombre del Archivo <span class="required">*</span></label>
                    <input type="text" id="edit-nom-archivo" name="txt_edit_nom_archivo" class="form-input" minlength="3" maxlength="30">
                    <span class="field-error" id="err-edit-nombre"></span>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Actualizar Archivo</button>
        </div>
    </div>
</div>

<!-- MODAL: DETALLE DE ARCHIVO PLANO -->
<div id="modal-detail" class="modal-overlay hidden">
    <div class="modal-box modal-box-lg">
        <div class="modal-header blue">
            <div><h2 id="detail-title">Detalle de Archivo Plano</h2><p id="detail-subtitle"></p></div>
            <button class="modal-close" id="close-detail-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <div id="detail-content"></div>
            <h4 class="detail-subheading"><i class="fas fa-list"></i> Pagos Incluidos</h4>
            <div id="detalle-pagos-list">
                <div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>Cargando...</p></div>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" id="close-detail-btn">Cerrar</button>
            <button type="button" id="detail-btn-download" class="btn btn-primary"><i class="fas fa-download"></i> Descargar CSV</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<!-- CALENDARIO FLOTANTE (mismo estilo que Festivos). Solo deja elegir los días
     de pago de Parámetros de Tesorería que no sean festivo — lo arma archivo_plano.js -->
<div id="dp-pop" class="dp-pop hidden" role="dialog" aria-label="Seleccionar fecha">
    <div class="dp-head">
        <div class="dp-nav-grupo">
            <button type="button" class="dp-nav" id="dp-prev-anio" aria-label="Año anterior" title="Año anterior"><i class="fas fa-angles-left"></i></button>
            <button type="button" class="dp-nav" id="dp-prev" aria-label="Mes anterior" title="Mes anterior"><i class="fas fa-chevron-left"></i></button>
        </div>
        <strong id="dp-titulo"></strong>
        <div class="dp-nav-grupo">
            <button type="button" class="dp-nav" id="dp-next" aria-label="Mes siguiente" title="Mes siguiente"><i class="fas fa-chevron-right"></i></button>
            <button type="button" class="dp-nav" id="dp-next-anio" aria-label="Año siguiente" title="Año siguiente"><i class="fas fa-angles-right"></i></button>
        </div>
    </div>
    <div class="dp-semana">
        <span>Dom</span><span>Lun</span><span>Mar</span><span>Mié</span><span>Jue</span><span>Vie</span><span>Sáb</span>
    </div>
    <div class="dp-grid" id="dp-grid"></div>
    <div class="dp-info" id="dp-info"></div>
    <div class="dp-leyenda">
        <span><i class="l-pago"></i>Día de pago</span>
        <span><i class="l-festivo"></i>Festivo</span>
        <span><i class="l-hoy"></i>Hoy</span>
    </div>
    <div class="dp-acciones">
        <button type="button" class="dp-accion" id="dp-hoy">Próxima fecha válida</button>
        <button type="button" class="dp-accion secundaria" id="dp-borrar">Borrar</button>
    </div>
</div>

<!-- Días de pago y festivos para el calendario (los usa el JS) -->
<script type="application/json" id="calendario-pagos-json"><?= json_encode([
    'dias_pago' => $dias_pago,
    'festivos'  => (object)$festivos,
], JSON_UNESCAPED_UNICODE | JSON_HEX_TAG) ?></script>

<!-- SCRIPTS JS -->
<script src="modules/tescxp/js/archivo_plano.js"></script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
