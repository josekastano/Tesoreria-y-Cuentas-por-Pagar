<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Tipos de Pago";
$page_description = "Gestión de los tipos de pago (proveedores, nómina u otros)";
$page_icon        = "bi-wallet2";
$page_extra_css   = ["../modules/tescxp/css/tipos_pago.css"];
$page_extra_js    = ["../modules/tescxp/js/tipos_pago.js"];
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// SENTENCIAS PREPARADAS (todas en prepare_tescxp.php, bloque 8)
// ------------------------------------------------------------
//  $list_tipos_pago_admin  listado con activos e inactivos
//  $get_tipo_pago_admin    un tipo de pago (activo o no)
//  $check_nom_tipo_pago    nombre repetido en otro ID
//  $ins_tipo_pago          fun_insert_tipos_pago(id, nombre)
//  $upd_tipo_pago          fun_update_tipos_pago(id, nombre, ind_borrado)
//  $del_tipo_pago          fun_delete_tipos_pago(id)  (borrado lógico)
// Las validaciones de PHP solo sirven para marcar el campo con error en
// el formulario; las reglas de verdad están en las funciones.
// ============================================================

// ============================================================
// HELPERS
// ============================================================
if (!function_exists('limpiar_error_pgsql')) {
function limpiar_error_pgsql(string $msg): string {
    if (preg_match('/ERROR:\s*ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    if (preg_match('/ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    return $msg;
}
}

// ============================================================
// TEXTO UTF-8 SIN DEPENDER DE mbstring
// ------------------------------------------------------------
// Si la extensión mbstring no está activa en php.ini, mb_strtoupper,
// mb_strlen, etc. no existen y PHP termina con error fatal (el
// navegador recibe "Respuesta inválida del servidor"). Estas funciones
// usan mbstring si está y, si no, una alternativa equivalente.
// ============================================================
if (!function_exists('txt_mayusculas')) {
    function txt_mayusculas(string $s): string {
        if (function_exists('mb_strtoupper')) {
            return mb_strtoupper($s, 'UTF-8');
        }
        // strtoupper solo cambia letras ASCII; las tildes y la ñ se pasan aparte
        return strtr(strtoupper($s), ['á' => 'Á', 'é' => 'É', 'í' => 'Í', 'ó' => 'Ó', 'ú' => 'Ú',
                                      'ü' => 'Ü', 'ñ' => 'Ñ']);
    }
}
if (!function_exists('txt_largo')) {
    function txt_largo(string $s): int {
        if (function_exists('mb_strlen')) {
            return mb_strlen($s, 'UTF-8');
        }
        $n = preg_match_all('/./us', $s);
        return $n === false ? strlen($s) : $n;
    }
}
if (!function_exists('txt_a_utf8')) {
    // Mensajes de PostgreSQL en Windows pueden llegar en Windows-1252
    function txt_a_utf8(string $s): string {
        if (preg_match('//u', $s) === 1) {
            return $s;                                   // ya es UTF-8 válido
        }
        if (function_exists('mb_convert_encoding')) {
            return mb_convert_encoding($s, 'UTF-8', 'Windows-1252');
        }
        if (function_exists('iconv')) {
            $r = @iconv('Windows-1252', 'UTF-8//IGNORE', $s);
            if ($r !== false) return $r;
        }
        return $s;   // json_encode lo arregla con JSON_INVALID_UTF8_SUBSTITUTE
    }
}

// ============================================================
// RESPONDER JSON
// ------------------------------------------------------------
// menu_principal.php ya imprimió el layout (HTML del menú) antes de
// incluir esta página. Si se hace un echo directo, la respuesta queda
// "HTML + JSON" y el navegador no la puede leer ("Respuesta inválida
// del servidor"). Esta función descarta todo lo que haya en los buffers
// de salida y envía SOLO el JSON.
// ============================================================
if (!function_exists('responder_json')) {
    function responder_json(array $respuesta): void {
        $previo = '';
        while (ob_get_level() > 0) {
            $previo = ((string)ob_get_clean()) . $previo;
        }
        // Si antes del JSON hubo un warning/error de PHP, se devuelve para verlo en consola
        $previo = trim(strip_tags($previo));
        if ($previo !== '' && preg_match('/(fatal|error|warning|notice|deprecated|exception)/i', $previo)) {
            $respuesta['debug_salida_previa'] = substr($previo, 0, 800);
        }
        // Mensajes de PostgreSQL en Windows pueden llegar en otra codificación
        if (isset($respuesta['message']) && is_string($respuesta['message'])) {
            $respuesta['message'] = txt_a_utf8($respuesta['message']);
        }
        if (!headers_sent()) {
            header('Content-Type: application/json; charset=utf-8');
        }
        echo json_encode($respuesta, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
        exit;
    }
}

// PDO pgsql puede devolver el booleano como true/false o como 't'/'f'
if (!function_exists('es_verdadero')) {
function es_verdadero($v): bool {
    return in_array($v, [true, 1, '1', 't', 'true', 'TRUE'], true);
}
}

// Valida el nombre (1 a 15 caracteres, como el CHECK de la tabla)
if (!function_exists('validar_nombre_tipo_pago')) {
function validar_nombre_tipo_pago(string $nombre): ?string {
    $largo = txt_largo($nombre);
    if ($largo < 1 || $largo > 15) {
        return 'El nombre debe tener entre 1 y 15 caracteres.';
    }
    if (!preg_match('/^[\p{L}\p{N} .\-]+$/u', $nombre)) {
        return 'Solo se permiten letras, números, espacios, puntos y guiones.';
    }
    return null;
}
}

// Trae un tipo de pago (activo o no); si no existe lanza una excepción
if (!function_exists('buscar_tipo_pago')) {
function buscar_tipo_pago(PDOStatement $stmt, int $id): array {
    $stmt->execute([':wid_tipo_pago' => $id]);
    $fila = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($fila === false) {
        throw new Exception('El tipo de pago no existe.');
    }
    return $fila;
}
}

if (!function_exists('nombre_duplicado')) {
function nombre_duplicado(PDOStatement $stmt, string $nombre, int $id): bool {
    $stmt->execute([':wnom_tipo_pago' => $nombre, ':wid_tipo_pago' => $id]);
    return (int)$stmt->fetchColumn() > 0;
}
}

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    ob_start();   // todo lo que se imprima por error queda aquí y responder_json lo descarta
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- NUEVO TIPO DE PAGO ----------
        if (isset($_POST['btn_nuevo'])) {
            $id_tipo_pago  = (int)($_POST['sel_id_tipo_pago'] ?? 0);
            $nom_tipo_pago = txt_mayusculas(trim($_POST['txt_nom_tipo_pago'] ?? ''));

            $errores = [];

            if ($id_tipo_pago < 1 || $id_tipo_pago > 9) {
                $errores['err-new-id'] = 'Seleccione un ID entre 1 y 9.';
            } else {
                $get_tipo_pago_admin->execute([':wid_tipo_pago' => $id_tipo_pago]);
                $existente = $get_tipo_pago_admin->fetch(PDO::FETCH_ASSOC);
                if ($existente !== false) {
                    $errores['err-new-id'] = es_verdadero($existente['ind_borrado'])
                        ? "El ID {$id_tipo_pago} existe pero está inactivo: actívelo desde la tabla."
                        : "El ID {$id_tipo_pago} ya está en uso.";
                }
            }

            if ($err = validar_nombre_tipo_pago($nom_tipo_pago)) {
                $errores['err-new-nombre'] = $err;
            } elseif (nombre_duplicado($check_nom_tipo_pago, $nom_tipo_pago, $id_tipo_pago)) {
                $errores['err-new-nombre'] = 'Ya existe un tipo de pago con ese nombre.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                responder_json($respuesta);
            }

            $ins_tipo_pago->execute([
                ':wid_tipo_pago'  => $id_tipo_pago,
                ':wnom_tipo_pago' => $nom_tipo_pago,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Tipo de pago registrado correctamente.';
            responder_json($respuesta);
        }

        // ---------- EDITAR TIPO DE PAGO ----------
        // El ID es la llave primaria: no se modifica, solo el nombre.
        if (isset($_POST['btn_editar'])) {
            $id_tipo_pago  = (int)($_POST['hid_edit_id'] ?? 0);
            $nom_tipo_pago = txt_mayusculas(trim($_POST['txt_edit_nom_tipo_pago'] ?? ''));

            $errores = [];

            if ($id_tipo_pago < 1 || $id_tipo_pago > 9) {
                $errores['err-edit-id'] = 'ID de tipo de pago no válido.';
            }
            if ($err = validar_nombre_tipo_pago($nom_tipo_pago)) {
                $errores['err-edit-nombre'] = $err;
            } elseif (nombre_duplicado($check_nom_tipo_pago, $nom_tipo_pago, $id_tipo_pago)) {
                $errores['err-edit-nombre'] = 'Ya existe otro tipo de pago con ese nombre.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                responder_json($respuesta);
            }

            // Se conserva el estado actual (editar no activa ni inactiva)
            $actual = buscar_tipo_pago($get_tipo_pago_admin, $id_tipo_pago);

            $upd_tipo_pago->execute([
                ':wid_tipo_pago'  => $id_tipo_pago,
                ':wnom_tipo_pago' => $nom_tipo_pago,
                ':wind_borrado'   => es_verdadero($actual['ind_borrado']) ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Tipo de pago actualizado correctamente.';
            responder_json($respuesta);
        }

        // ---------- ACTIVAR / INACTIVAR (BORRADO LÓGICO) ----------
        if (isset($_POST['btn_estado'])) {
            $id_tipo_pago = (int)($_POST['hid_est_id'] ?? 0);
            $accion       = $_POST['hid_est_accion'] ?? '';

            if ($id_tipo_pago < 1 || $id_tipo_pago > 9) {
                throw new Exception('ID de tipo de pago no válido.');
            }
            if (!in_array($accion, ['activar', 'inactivar'], true)) {
                throw new Exception('Acción no válida.');
            }

            if ($accion === 'inactivar') {
                // fun_delete_tipos_pago: borrado lógico (no deja si hay archivos planos sin generar)
                $del_tipo_pago->execute([':wid_tipo_pago' => $id_tipo_pago]);
            } else {
                // fun_update_tipos_pago con ind_borrado = FALSE: reactiva conservando el nombre
                $actual = buscar_tipo_pago($get_tipo_pago_admin, $id_tipo_pago);
                $upd_tipo_pago->execute([
                    ':wid_tipo_pago'  => $id_tipo_pago,
                    ':wnom_tipo_pago' => $actual['nom_tipo_pago'],
                    ':wind_borrado'   => 'false',
                ]);
            }

            $respuesta['success'] = true;
            $respuesta['message'] = $accion === 'inactivar'
                ? 'Tipo de pago inactivado correctamente.'
                : 'Tipo de pago activado correctamente.';
            responder_json($respuesta);
        }

        $respuesta['message'] = 'Acción no válida.';
        responder_json($respuesta);

    } catch (Throwable $e) {
        // Los mensajes vienen de las funciones (RAISE EXCEPTION) o de PHP
        $mensaje = limpiar_error_pgsql($e->getMessage());
        $respuesta['message'] = $mensaje ?: $e->getMessage();
        responder_json($respuesta);
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_tipos_pago_admin->execute();
$tipos_pago = $list_tipos_pago_admin->fetchAll(PDO::FETCH_ASSOC);

foreach ($tipos_pago as &$t) {
    $t['id_tipo_pago'] = (int)$t['id_tipo_pago'];
    $t['ind_borrado']  = es_verdadero($t['ind_borrado']);
}
unset($t);

// IDs libres (1 a 9) para el modal de nuevo
$ids_usados = array_column($tipos_pago, 'id_tipo_pago');
$ids_libres = array_values(array_diff(range(1, 9), $ids_usados));

$total      = count($tipos_pago);
$activos    = count(array_filter($tipos_pago, fn($t) => !$t['ind_borrado']));
$inactivos  = $total - $activos;
$disponibles = count($ids_libres);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
<link rel="stylesheet" href="modules/tescxp/css/tipos_pago.css">
<div id="mod-tipos-pago" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Tipos de Pago</h1>
            <p>Gestión de los tipos de pago: proveedores, nómina u otros</p>
        </div>
        <button id="btn-add-tipo-pago" class="btn btn-primary"
                <?= $disponibles === 0 ? 'disabled title="Ya se usaron los 9 ID disponibles"' : '' ?>>
            <i class="fas fa-plus"></i> Nuevo Tipo de Pago
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-wallet"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total</div>
                <div class="stat-value"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
            <div class="stat-info">
                <div class="stat-label">Activos</div>
                <div class="stat-value"><?= $activos ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon red"><i class="fas fa-ban"></i></div>
            <div class="stat-info">
                <div class="stat-label">Inactivos</div>
                <div class="stat-value"><?= $inactivos ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-hashtag"></i></div>
            <div class="stat-info">
                <div class="stat-label">ID disponibles</div>
                <div class="stat-value"><?= $disponibles ?> <small>/ 9</small></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="tipo-pago-search" class="search-input" placeholder="Buscar por ID o nombre...">
        </div>
        <div class="filter-toggle-group" id="tipo-pago-estado-filtro">
            <button type="button" class="filter-toggle active" data-estado="todos">Todos</button>
            <button type="button" class="filter-toggle" data-estado="activo">Activos</button>
            <button type="button" class="filter-toggle" data-estado="inactivo">Inactivos</button>
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="tipos-pago-page-size">Filas por página</label>
            <select id="tipos-pago-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="tipos-pago-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="tipos-pago-table-scroll">
        <table class="data-table">
            <colgroup>
                <col class="col-id">
                <col class="col-nombre">
                <col class="col-estado">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="number">ID <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="text">Nombre del Tipo de Pago <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="2" data-sort-type="number">Estado <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="tipos-pago-tbody">
            <?php if (empty($tipos_pago)): ?>
                <tr class="empty-row">
                    <td colspan="4">
                        <div class="empty-state">
                            <i class="fas fa-wallet"></i>
                            <p>No hay tipos de pago registrados</p>
                            <span>Haga clic en "Nuevo Tipo de Pago" para agregar el primero</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($tipos_pago as $t):
                    $id         = $t['id_tipo_pago'];
                    $nombre_esc = htmlspecialchars($t['nom_tipo_pago'], ENT_QUOTES, 'UTF-8');
                    $borrado    = $t['ind_borrado'];
                ?>
                <tr data-id="<?= $id ?>" data-nombre="<?= $nombre_esc ?>" data-estado="<?= $borrado ? 'inactivo' : 'activo' ?>"
                    class="<?= $borrado ? 'fila-inactiva' : '' ?>">
                    <td data-sort="<?= $id ?>"><strong>#<?= $id ?></strong></td>
                    <td data-sort="<?= $nombre_esc ?>"><?= $nombre_esc ?></td>
                    <td data-sort="<?= $borrado ? 1 : 0 ?>">
                        <?php if ($borrado): ?>
                            <span class="badge badge-inactive">Inactivo</span>
                        <?php else: ?>
                            <span class="badge badge-active">Activo</span>
                        <?php endif; ?>
                    </td>
                    <td class="text-center">
                        <button type="button" class="btn-icon-sm edit btn-editar" title="Editar">
                            <i class="fas fa-edit"></i>
                        </button>
                        <?php if ($borrado): ?>
                            <button type="button" class="btn-icon-sm activate btn-estado" data-accion="activar" title="Activar">
                                <i class="fas fa-undo"></i>
                            </button>
                        <?php else: ?>
                            <button type="button" class="btn-icon-sm reject btn-estado" data-accion="inactivar" title="Inactivar">
                                <i class="fas fa-ban"></i>
                            </button>
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
                <span class="pagination-range" id="tipos-pago-range">0 de 0</span>
                <button type="button" id="tipos-pago-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="tipos-pago-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVO TIPO DE PAGO -->
<div id="modal-new-tipo-pago" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header green">
            <div>
                <h2>Nuevo Tipo de Pago</h2>
                <p>Registre un nuevo tipo de pago</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-tipo-pago-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label" for="new-tipo-pago-id">ID <span class="required">*</span></label>
                    <select id="new-tipo-pago-id" name="sel_id_tipo_pago" class="form-select">
                        <?php foreach ($ids_libres as $i => $libre): ?>
                            <option value="<?= $libre ?>" <?= $i === 0 ? 'selected' : '' ?>><?= $libre ?></option>
                        <?php endforeach; ?>
                    </select>
                    <span class="field-hint">Solo se muestran los ID libres (del 1 al 9).</span>
                    <span class="field-error" id="err-new-id"></span>
                </div>
                <div class="form-field">
                    <label class="form-label" for="new-tipo-pago-nombre">Nombre del Tipo de Pago <span class="required">*</span></label>
                    <input type="text" id="new-tipo-pago-nombre" name="txt_nom_tipo_pago" class="form-input input-mayus"
                           placeholder="Ej: PROVEEDORES" maxlength="15" autocomplete="off" data-contador="new-contador">
                    <span class="field-hint contador" id="new-contador">0 / 15</span>
                    <span class="field-error" id="err-new-nombre"></span>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Tipo de Pago</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR TIPO DE PAGO -->
<div id="modal-edit-tipo-pago" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header blue">
            <div>
                <h2>Editar Tipo de Pago</h2>
                <p>Modifique el nombre del tipo de pago</p>
            </div>
            <button class="modal-close btn-close-edit-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-tipo-pago-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id" id="edit-tipo-pago-id" value="">
                <div class="form-field">
                    <label class="form-label" for="edit-tipo-pago-id-ver">ID</label>
                    <input type="text" id="edit-tipo-pago-id-ver" class="form-input" disabled>
                    <span class="field-hint">El ID no se puede cambiar.</span>
                    <span class="field-error" id="err-edit-id"></span>
                </div>
                <div class="form-field">
                    <label class="form-label" for="edit-tipo-pago-nombre">Nombre del Tipo de Pago <span class="required">*</span></label>
                    <input type="text" id="edit-tipo-pago-nombre" name="txt_edit_nom_tipo_pago" class="form-input input-mayus"
                           maxlength="15" autocomplete="off" data-contador="edit-contador">
                    <span class="field-hint contador" id="edit-contador">0 / 15</span>
                    <span class="field-error" id="err-edit-nombre"></span>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Actualizar Tipo de Pago</button>
        </div>
    </div>
</div>

<!-- MODAL: CONFIRMAR ACTIVAR / INACTIVAR -->
<div id="modal-confirm-estado" class="modal-overlay hidden">
    <div class="modal-box confirm-box">
        <div class="confirm-icon" id="confirm-estado-icon"><i class="fas fa-exclamation-triangle"></i></div>
        <h4 id="confirm-estado-title"></h4>
        <p id="confirm-estado-body"></p>
        <div class="confirm-buttons">
            <button type="button" class="btn-cancelar" id="confirm-estado-cancel-btn">Cancelar</button>
            <button type="button" class="btn-eliminar" id="confirm-estado-ok-btn">Sí, inactivar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<script src="modules/tescxp/js/tipos_pago.js"></script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
