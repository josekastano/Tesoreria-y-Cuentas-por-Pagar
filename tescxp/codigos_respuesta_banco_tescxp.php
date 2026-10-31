<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Códigos de Respuesta del Banco";
$page_description = "Catálogo de los códigos que devuelve cada banco en su archivo de respuesta";
$page_icon        = "bi-upc-scan";
$page_extra_css   = ["../modules/tescxp/css/codigos_respuesta_banco_tescxp.css"];
$page_extra_js    = ["../modules/tescxp/js/codigos_respuesta_banco_tescxp.js"];
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// LIMPIAR MENSAJE DE ERROR DE POSTGRESQL
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

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
// La llave de tab_codigos_respuesta_banco es (id_codigo, id_banco): el mismo
// código puede existir en dos bancos con significados distintos.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    ob_start();   // todo lo que se imprima por error queda aquí y responder_json lo descarta
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- NUEVO CÓDIGO ----------
        if (isset($_POST['btn_nuevo'])) {
            $id_codigo  = trim($_POST['txt_id_codigo']  ?? '');
            $id_banco   = trim($_POST['sel_id_banco']   ?? '');
            $des_motivo = trim($_POST['txt_des_motivo'] ?? '');

            $errores = [];

            // id_codigo VARCHAR(10) CHECK(LENGTH 1..10)
            if ($id_codigo === '' || txt_largo($id_codigo) > 10) {
                $errores['err-new-codigo'] = 'El código debe tener entre 1 y 10 caracteres.';
            }

            // id_banco: debe venir del select
            if ($id_banco === '') {
                $errores['err-new-banco'] = 'Seleccione el banco.';
            }

            // des_motivo VARCHAR(100) CHECK(LENGTH >= 3)
            if (txt_largo($des_motivo) < 3 || txt_largo($des_motivo) > 100) {
                $errores['err-new-descripcion'] = 'La descripción debe tener entre 3 y 100 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                responder_json($respuesta);
            }

            $ins_codigo_respuesta->execute([
                ':wid_codigo'  => $id_codigo,
                ':wid_banco'   => $id_banco,
                ':wdes_motivo' => $des_motivo,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Código de respuesta registrado correctamente.';
            responder_json($respuesta);
        }

        // ---------- EDITAR CÓDIGO (solo la descripción) ----------
        // El código y el banco son la llave y no se cambian. Se reenvía el
        // ind_borrado actual para no reactivar ni dar de baja al editar.
        if (isset($_POST['btn_editar'])) {
            $id_codigo   = trim($_POST['hid_edit_id_codigo']   ?? '');
            $id_banco    = trim($_POST['hid_edit_id_banco']    ?? '');
            $des_motivo  = trim($_POST['txt_edit_des_motivo']  ?? '');
            $ind_borrado = ($_POST['hid_edit_ind_borrado'] ?? 'false') === 'true' ? 'true' : 'false';

            $errores = [];

            if ($id_codigo === '' || $id_banco === '') {
                $errores['err-edit-descripcion'] = 'Código no válido.';
            }
            if (txt_largo($des_motivo) < 3 || txt_largo($des_motivo) > 100) {
                $errores['err-edit-descripcion'] = 'La descripción debe tener entre 3 y 100 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                responder_json($respuesta);
            }

            $upd_codigo_respuesta->execute([
                ':wid_codigo'   => $id_codigo,
                ':wid_banco'    => $id_banco,
                ':wdes_motivo'  => $des_motivo,
                ':wind_borrado' => $ind_borrado,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Código de respuesta actualizado correctamente.';
            responder_json($respuesta);
        }

        // ---------- REACTIVAR CÓDIGO DADO DE BAJA ----------
        if (isset($_POST['btn_reactivar'])) {
            $id_codigo  = trim($_POST['hid_id_codigo']  ?? '');
            $id_banco   = trim($_POST['hid_id_banco']   ?? '');
            $des_motivo = trim($_POST['hid_des_motivo'] ?? '');

            if ($id_codigo === '' || $id_banco === '' || $des_motivo === '') {
                throw new Exception('Código no válido.');
            }

            $upd_codigo_respuesta->execute([
                ':wid_codigo'   => $id_codigo,
                ':wid_banco'    => $id_banco,
                ':wdes_motivo'  => $des_motivo,
                ':wind_borrado' => 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Código reactivado correctamente.';
            responder_json($respuesta);
        }

        // ---------- DAR DE BAJA (borrado lógico) ----------
        // ind_borrado = TRUE: el código deja de ofrecerse al registrar la
        // respuesta del banco, pero los pagos que ya lo usan lo conservan.
        if (isset($_POST['btn_eliminar'])) {
            $id_codigo = trim($_POST['hid_id_codigo'] ?? '');
            $id_banco  = trim($_POST['hid_id_banco']  ?? '');

            if ($id_codigo === '' || $id_banco === '') {
                throw new Exception('Código no válido.');
            }

            $del_codigo_respuesta->execute([
                ':wid_codigo' => $id_codigo,
                ':wid_banco'  => $id_banco,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Código dado de baja correctamente.';
            responder_json($respuesta);
        }

        // Si no se reconoce ninguna acción
        $respuesta['message'] = 'Acción no válida.';
        responder_json($respuesta);

    } catch (Throwable $e) {
        $mensaje = limpiar_error_pgsql($e->getMessage());
        if (empty($mensaje)) {
            $mensaje = $e->getMessage();
        }
        // Llave primaria duplicada -> código repetido en el mismo banco
        if (stripos($mensaje, 'duplicate key') !== false || stripos($mensaje, 'llave duplicada') !== false) {
            $mensaje = 'Ese código ya está registrado para ese banco.';
        }
        $respuesta['message'] = $mensaje;
        responder_json($respuesta);
    }
}

// ============================================================
// CARGAR DATOS (SOLO PARA LA VISTA INICIAL)
// ============================================================
// $list_codigos_respuesta trae activos e inactivos (ind_borrado), para poder
// reactivar desde aquí un código dado de baja.
$list_codigos_respuesta->execute();
$codigos = $list_codigos_respuesta->fetchAll(PDO::FETCH_ASSOC);

// Bancos activos: para el select del modal "Nuevo código"
$list_bancos->execute();
$bancos = $list_bancos->fetchAll(PDO::FETCH_ASSOC);

// Bancos que aparecen en la tabla: para el filtro por banco
$bancos_filtro = [];
foreach ($codigos as $c) {
    $bancos_filtro[$c['id_banco']] = $c['nom_banco'];
}
asort($bancos_filtro);

$es_borrado = fn($c) => in_array($c['ind_borrado'], [true, 't', 'true', 1, '1'], true);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
<link rel="stylesheet" href="modules/tescxp/css/codigos_respuesta_banco_tescxp.css">
<div id="mod-codigos" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Códigos de Respuesta del Banco</h1>
            <p>Catálogo de los códigos que devuelve cada banco en su archivo de respuesta</p>
        </div>
        <button id="btn-add-codigo" class="btn btn-primary">
            <i class="fas fa-plus"></i> Nuevo Código
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <?php
        $total      = count($codigos);
        $inactivos  = count(array_filter($codigos, $es_borrado));
        $activos    = $total - $inactivos;
        $num_bancos = count($bancos_filtro);
        ?>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-list-ul"></i></div>
            <div class="stat-info">
                <div class="stat-label">Códigos activos</div>
                <div class="stat-value" id="stat-activos"><?= $activos ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon red"><i class="fas fa-ban"></i></div>
            <div class="stat-info">
                <div class="stat-label">Dados de baja</div>
                <div class="stat-value" id="stat-inactivos"><?= $inactivos ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-university"></i></div>
            <div class="stat-info">
                <div class="stat-label">Bancos con códigos</div>
                <div class="stat-value" id="stat-bancos"><?= $num_bancos ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="codigo-search" class="search-input" placeholder="Buscar por código, banco o descripción...">
        </div>
        <select id="codigo-banco-filter" class="filter-select" aria-label="Filtrar por banco">
            <option value="">Todos los bancos</option>
            <?php foreach ($bancos_filtro as $id => $nom): ?>
                <option value="<?= htmlspecialchars($id) ?>"><?= htmlspecialchars($nom) ?></option>
            <?php endforeach; ?>
        </select>
        <div class="filter-toggle-group">
            <button class="filter-toggle" data-filter="all">Todos</button>
            <button class="filter-toggle active" data-filter="activo">Activos</button>
            <button class="filter-toggle" data-filter="inactivo">Dados de baja</button>
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="codigos-page-size">Filas por página</label>
            <select id="codigos-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="codigos-count"><?= $activos ?> resultado<?= $activos !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="codigos-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-codigo">
                <col class="col-banco">
                <col class="col-descripcion">
                <col class="col-estado">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="text">Código <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="text">Banco <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="2" data-sort-type="text">Descripción <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="3" data-sort-type="text">Estado <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="codigos-tbody">
            <?php if (empty($codigos)): ?>
                <tr class="empty-row">
                    <td colspan="5">
                        <div class="empty-state">
                            <i class="fas fa-barcode"></i>
                            <p>No hay códigos de respuesta registrados</p>
                            <span>Haga clic en "Nuevo Código" para agregar el primero</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($codigos as $c):
                    $borrado = $es_borrado($c);
                    $estado  = $borrado ? 'inactivo' : 'activo';
                    $datos   = [
                        'id_codigo'   => $c['id_codigo'],
                        'id_banco'    => $c['id_banco'],
                        'nom_banco'   => $c['nom_banco'],
                        'des_motivo'  => $c['des_motivo'],
                        'ind_borrado' => $borrado,
                    ];
                    $json = htmlspecialchars(json_encode($datos, JSON_UNESCAPED_UNICODE), ENT_QUOTES);
                ?>
                <tr data-estado="<?= $estado ?>" data-banco="<?= htmlspecialchars($c['id_banco']) ?>">
                    <td data-sort="<?= htmlspecialchars($c['id_codigo']) ?>"><span class="cod-bancario"><?= htmlspecialchars($c['id_codigo']) ?></span></td>
                    <td data-sort="<?= htmlspecialchars($c['nom_banco']) ?>"><?= htmlspecialchars($c['nom_banco']) ?></td>
                    <td data-sort="<?= htmlspecialchars($c['des_motivo']) ?>"><?= htmlspecialchars($c['des_motivo']) ?></td>
                    <td data-sort="<?= $estado ?>">
                        <?php if ($borrado): ?>
                            <span class="badge badge-inactive">De baja</span>
                        <?php else: ?>
                            <span class="badge badge-active">Activo</span>
                        <?php endif; ?>
                    </td>
                    <td class="text-center">
                        <button class="btn-icon-sm edit" title="Editar" data-codigo="<?= $json ?>" data-action="editar">
                            <i class="fas fa-edit"></i>
                        </button>
                        <?php if ($borrado): ?>
                            <button class="btn-icon-sm toggle" title="Reactivar" data-codigo="<?= $json ?>" data-action="reactivar">
                                <i class="fas fa-undo"></i>
                            </button>
                        <?php else: ?>
                            <button class="btn-icon-sm reject" title="Dar de baja" data-codigo="<?= $json ?>" data-action="eliminar">
                                <i class="fas fa-trash"></i>
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
                <span class="pagination-range" id="codigos-range">0 de 0</span>
                <button type="button" id="codigos-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="codigos-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVO CÓDIGO -->
<div id="modal-new-codigo" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header green">
            <div>
                <h2>Nuevo Código de Respuesta</h2>
                <p>Registre un código tal como lo envía el banco</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-codigo-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label">Banco <span class="required">*</span></label>
                    <select id="new-id-banco" name="sel_id_banco" class="form-select">
                        <option value="">Seleccione un banco</option>
                        <?php foreach ($bancos as $b): ?>
                            <option value="<?= htmlspecialchars($b['id_banco']) ?>"><?= htmlspecialchars($b['nom_banco']) ?></option>
                        <?php endforeach; ?>
                    </select>
                    <span class="field-error" id="err-new-banco"></span>
                    <p class="field-hint">Es el banco de la cuenta de la empresa desde la que se envía el archivo plano.</p>
                </div>
                <div class="form-field">
                    <label class="form-label">Código <span class="required">*</span></label>
                    <input type="text" id="new-id-codigo" name="txt_id_codigo" class="form-input" placeholder="Ej: R05" maxlength="10">
                    <span class="field-error" id="err-new-codigo"></span>
                    <p class="field-hint">Escríbalo exactamente como viene en el archivo de respuesta del banco.</p>
                </div>
                <div class="form-field">
                    <label class="form-label">Descripción <span class="required">*</span></label>
                    <input type="text" id="new-des-motivo" name="txt_des_motivo" class="form-input" placeholder="Ej: Cuenta embargada" minlength="3" maxlength="100">
                    <span class="field-error" id="err-new-descripcion"></span>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Código</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR CÓDIGO -->
<div id="modal-edit-codigo" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header blue">
            <div>
                <h2>Editar Código de Respuesta</h2>
                <p>Modifique la descripción del código</p>
            </div>
            <button class="modal-close btn-close-edit-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-codigo-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id_codigo"   id="edit-id-codigo-hid"   value="">
                <input type="hidden" name="hid_edit_id_banco"    id="edit-id-banco-hid"    value="">
                <input type="hidden" name="hid_edit_ind_borrado" id="edit-ind-borrado-hid" value="false">
                <div class="form-grid">
                    <div class="form-field">
                        <label class="form-label">Banco</label>
                        <input type="text" id="edit-banco-display" class="form-input" disabled="disabled">
                    </div>
                    <div class="form-field">
                        <label class="form-label">Código</label>
                        <input type="text" id="edit-codigo-display" class="form-input" disabled="disabled">
                    </div>
                </div>
                <p class="field-hint form-hint-top">El banco y el código forman la llave y no se pueden modificar.</p>
                <div class="form-field">
                    <label class="form-label">Descripción <span class="required">*</span></label>
                    <input type="text" id="edit-des-motivo" name="txt_edit_des_motivo" class="form-input" minlength="3" maxlength="100">
                    <span class="field-error" id="err-edit-descripcion"></span>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Actualizar Código</button>
        </div>
    </div>
</div>

<!-- MODAL: CONFIRMAR ACCIÓN (estilo módulo Compras) -->
<div id="modal-confirm-eliminar" class="modal-overlay hidden">
    <div class="modal-box confirm-box">
        <div class="confirm-icon"><i class="fas fa-exclamation-triangle"></i></div>
        <h4 id="confirm-eliminar-title"></h4>
        <p id="confirm-eliminar-body"></p>
        <div class="confirm-buttons">
            <button type="button" class="btn-cancelar" id="confirm-eliminar-cancel-btn">Cancelar</button>
            <button type="button" class="btn-eliminar" id="confirm-eliminar-ok-btn">Sí, dar de baja</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<script src="modules/tescxp/js/codigos_respuesta_banco_tescxp.js"></script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
