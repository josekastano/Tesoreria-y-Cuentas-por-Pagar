<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Cuentas de la Empresa";
$page_description = "Gestión de cuentas bancarias propias para pagos a proveedores";
$page_icon        = "bi-bank";
$page_extra_css   = ["../modules/tescxp/css/ctas_empresa.css"];
$page_extra_js    = ["../modules/tescxp/js/ctas_empresa.js"];
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// NIT DE LA EMPRESA (fijo, viene de Parámetros Generales)
// ============================================================
$list_pmtros_grales->execute();
$pmtros_grales   = $list_pmtros_grales->fetch(PDO::FETCH_ASSOC);
$id_empresa_fijo = $pmtros_grales['id_empresa'] ?? '';


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
// CARGAR SELECTS (siempre se cargan para la vista inicial)
// ============================================================
$list_bancos->execute();
$bancos = $list_bancos->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- NUEVO BANCO RÁPIDO (modal dentro de "Nueva Cuenta") ----------
        // Crea el banco sin recargar la página y devuelve sus datos para que
        // el JS lo agregue al select y lo deje seleccionado.
        if (isset($_POST['btn_nuevo_banco'])) {
            $id_banco  = trim($_POST['txt_banco_id']     ?? '');
            $nom_banco = trim($_POST['txt_banco_nombre'] ?? '');

            $errores = [];

            if (mb_strlen($id_banco) < 6 || mb_strlen($id_banco) > 10) {
                $errores['err-banco-id'] = 'El código debe tener entre 6 y 10 caracteres.';
            }
            if (mb_strlen($nom_banco) < 4 || mb_strlen($nom_banco) > 50) {
                $errores['err-banco-nombre'] = 'El nombre debe tener entre 4 y 50 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            // Se crea siempre ACTIVO: un banco inactivo no serviría para la cuenta.
            $ins_banco->execute([
                ':wid_banco'   => $id_banco,
                ':wnom_banco'  => $nom_banco,
                ':wind_estado' => 'true',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Banco registrado correctamente.';
            $respuesta['banco']   = ['id_banco' => $id_banco, 'nom_banco' => $nom_banco];
            echo json_encode($respuesta);
            exit;
        }

        // ---------- NUEVA CUENTA ----------
        if (isset($_POST['btn_nuevo'])) {
            $cta_empresa    = trim($_POST['txt_cta_empresa']     ?? '');
            $id_banco       = trim($_POST['sel_id_banco']        ?? '');
            $ind_tipocuenta = ($_POST['sel_tipocuenta']          ?? 'false') === 'true';

            $errores = [];

            if (empty($id_empresa_fijo)) {
                $errores['err-new-id-empresa'] = 'No se encontró el NIT de la empresa en Parámetros Generales. Configure primero ese módulo.';
            }
            if (!preg_match('/^[0-9]{10,16}$/', $cta_empresa)) {
                $errores['err-new-cta'] = 'El número de cuenta debe tener entre 10 y 16 dígitos numéricos.';
            }
            if (empty($id_banco)) {
                $errores['err-new-banco'] = 'Seleccione un banco.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $ins_cta_empresa->execute([
                ':wid_empresa'     => $id_empresa_fijo,
                ':wcta_empresa'    => $cta_empresa,
                ':wid_banco'       => $id_banco,
                ':wind_tipocuenta' => $ind_tipocuenta ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Cuenta bancaria registrada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- EDITAR CUENTA ----------
        if (isset($_POST['btn_editar'])) {
            $id_empresa     = trim($_POST['hid_edit_id_empresa']  ?? '');
            $cta_empresa    = trim($_POST['hid_edit_cta_empresa'] ?? '');
            $id_banco       = trim($_POST['sel_edit_id_banco']    ?? '');
            $ind_tipocuenta = ($_POST['sel_edit_tipocuenta']      ?? 'false') === 'true';

            $errores = [];

            if (empty($id_empresa) || empty($cta_empresa)) {
                $errores['err-edit-banco'] = 'Cuenta no válida.';
            }
            if (empty($id_banco)) {
                $errores['err-edit-banco'] = 'Seleccione un banco.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $upd_cta_empresa->execute([
                ':wid_empresa'     => $id_empresa,
                ':wcta_empresa'    => $cta_empresa,
                ':wid_banco'       => $id_banco,
                ':wind_tipocuenta' => $ind_tipocuenta ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Cuenta bancaria actualizada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- ELIMINAR CUENTA ----------
        if (isset($_POST['btn_eliminar'])) {
            $id_empresa  = trim($_POST['hid_del_id_empresa']  ?? '');
            $cta_empresa = trim($_POST['hid_del_cta_empresa'] ?? '');

            if (empty($id_empresa) || empty($cta_empresa)) {
                throw new Exception('Cuenta no válida.');
            }

            $del_cta_empresa->execute([
                ':wid_empresa'  => $id_empresa,
                ':wcta_empresa' => $cta_empresa,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Cuenta bancaria eliminada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // Si no se reconoce ninguna acción
        $respuesta['message'] = 'Acción no válida.';
        echo json_encode($respuesta);
        exit;

    } catch (Exception $e) {
        $mensaje = limpiar_error_pgsql($e->getMessage());
        if (empty($mensaje)) {
            $mensaje = $e->getMessage();
        }

        // Banco rápido con código repetido: se muestra debajo del campo Código
        if (isset($_POST['btn_nuevo_banco']) &&
            (stripos($mensaje, 'ya existe') !== false ||
             stripos($mensaje, 'duplicate key') !== false ||
             stripos($mensaje, 'llave duplicada') !== false)) {
            $respuesta['errors'] = ['err-banco-id' => 'Ya existe un banco registrado con ese código.'];
            echo json_encode($respuesta);
            exit;
        }

        $respuesta['message'] = $mensaje;
        echo json_encode($respuesta);
        exit;
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_ctas_empresa->execute();
$ctas_empresa = $list_ctas_empresa->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
<link rel="stylesheet" href="modules/tescxp/css/ctas_empresa.css">
<div id="mod-ctas-empresa" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Cuentas de la Empresa</h1>
            <p>Cuentas bancarias propias utilizadas para el pago a proveedores</p>
        </div>
        <button id="btn-add-cuenta" class="btn btn-primary">
            <i class="fas fa-plus"></i> Nueva Cuenta
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <?php
        $total      = count($ctas_empresa);
        $corrientes = count(array_filter($ctas_empresa, fn($c) => $c['ind_tipocuenta'] === 't' || $c['ind_tipocuenta'] === true));
        $ahorros    = $total - $corrientes;
        $bancos_unicos = count(array_unique(array_column($ctas_empresa, 'id_banco')));
        ?>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-university"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total cuentas</div>
                <div class="stat-value" id="stat-total"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-money-check-alt"></i></div>
            <div class="stat-info">
                <div class="stat-label">Corrientes</div>
                <div class="stat-value" id="stat-corrientes"><?= $corrientes ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-piggy-bank"></i></div>
            <div class="stat-info">
                <div class="stat-label">Ahorros</div>
                <div class="stat-value" id="stat-ahorros"><?= $ahorros ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-landmark"></i></div>
            <div class="stat-info">
                <div class="stat-label">Bancos distintos</div>
                <div class="stat-value" id="stat-bancos"><?= $bancos_unicos ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="cuenta-search" class="search-input" placeholder="Buscar por número de cuenta o banco...">
        </div>
        <div class="filter-toggle-group">
            <button class="filter-toggle active" data-filter="all">Todas</button>
            <button class="filter-toggle" data-filter="corriente">Corrientes</button>
            <button class="filter-toggle" data-filter="ahorros">Ahorros</button>
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="cuentas-page-size">Filas por página</label>
            <select id="cuentas-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="cuentas-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="cuentas-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-nit">
                <col class="col-banco">
                <col class="col-cuenta">
                <col class="col-tipo">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th>NIT Empresa</th>
                    <th class="sortable" data-sort-key="1" data-sort-type="text">Banco <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="2" data-sort-type="text">Número de Cuenta <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Tipo</th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="cuentas-tbody">
            <?php if (empty($ctas_empresa)): ?>
                <tr class="empty-row">
                    <td colspan="5">
                        <div class="empty-state">
                            <i class="fas fa-university"></i>
                            <p>No hay cuentas bancarias registradas</p>
                            <span>Haga clic en "Nueva Cuenta" para agregar la primera</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($ctas_empresa as $c):
                    $es_corriente = ($c['ind_tipocuenta'] === 't' || $c['ind_tipocuenta'] === true);
                    $badge_tipo   = $es_corriente
                        ? '<span class="badge badge-active">Corriente</span>'
                        : '<span class="badge badge-inactive" style="background:#fffbeb;color:#f59e0b">Ahorros</span>';
                    $id_emp_esc   = htmlspecialchars($c['id_empresa']);
                    $cta_esc      = htmlspecialchars($c['cta_empresa']);
                    $filtro_tipo  = $es_corriente ? 'corriente' : 'ahorros';
                ?>
                <tr data-tipo="<?= $filtro_tipo ?>">
                    <td><strong><?= $id_emp_esc ?></strong></td>
                    <td data-sort="<?= htmlspecialchars($c['nom_banco']) ?>"><?= htmlspecialchars($c['nom_banco']) ?></td>
                    <td data-sort="<?= $cta_esc ?>"><?= $cta_esc ?></td>
                    <td class="text-center"><?= $badge_tipo ?></td>
                    <td class="text-center">
                        <button class="btn-icon-sm edit" onclick='openEditModal(<?= json_encode($c) ?>)'>
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn-icon-sm reject" onclick="eliminarCuenta('<?= $id_emp_esc ?>', '<?= $cta_esc ?>', '<?= htmlspecialchars($c['nom_banco'], ENT_QUOTES) ?>')">
                            <i class="fas fa-trash"></i>
                        </button>
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
                <span class="pagination-range" id="cuentas-range">0 de 0</span>
                <button type="button" id="cuentas-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="cuentas-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVA CUENTA -->
<div id="modal-new-cuenta" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header green">
            <div>
                <h2>Nueva Cuenta Bancaria</h2>
                <p>Registre una cuenta de la empresa</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-cuenta-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label">NIT de la Empresa</label>
                    <input type="text" id="new-id-empresa" class="form-input" value="<?= htmlspecialchars($id_empresa_fijo) ?>" disabled>
                    <span class="field-error" id="err-new-id-empresa"></span>
                    <p class="field-hint">Definido en Parámetros Generales. No se puede modificar desde aquí.</p>
                </div>
                <div class="form-field">
                    <div class="label-row">
                        <label class="form-label" for="new-id-banco">Banco <span class="required">*</span></label>
                        <button type="button" class="btn-link-inline" id="btn-open-banco-rapido">
                            <i class="fas fa-plus"></i> Nuevo banco
                        </button>
                    </div>
                    <select id="new-id-banco" name="sel_id_banco" class="form-select">
                        <option value=""><?= empty($bancos) ? 'No hay bancos registrados' : 'Seleccione...' ?></option>
                        <?php foreach ($bancos as $b): ?>
                            <option value="<?= htmlspecialchars($b['id_banco']) ?>"><?= htmlspecialchars($b['nom_banco']) ?></option>
                        <?php endforeach; ?>
                    </select>
                    <div id="new-banco-empty" class="empty-hint <?= empty($bancos) ? '' : 'hidden' ?>">
                        <i class="fas fa-info-circle"></i>
                        <span>Aún no hay bancos registrados.</span>
                        <button type="button" class="btn-link-inline" id="btn-empty-crear-banco">Crear banco aquí</button>
                    </div>
                    <span class="field-error" id="err-new-banco"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Número de Cuenta <span class="required">*</span></label>
                    <input type="text" id="new-cta-empresa" name="txt_cta_empresa" class="form-input" placeholder="Ej: 1234567890" minlength="10" maxlength="16">
                    <span class="field-error" id="err-new-cta"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Tipo de Cuenta</label>
                    <select id="new-tipocuenta" name="sel_tipocuenta" class="form-select">
                        <option value="false">Ahorros</option>
                        <option value="true">Corriente</option>
                    </select>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Cuenta</button>
        </div>
    </div>
</div>

<!-- MODAL ANIDADO: CREAR BANCO SIN SALIR DE "NUEVA CUENTA" -->
<div id="modal-banco-rapido" class="modal-overlay modal-nested hidden">
    <div class="modal-box modal-box-sm">
        <div class="modal-header green">
            <div>
                <h2>Nuevo Banco</h2>
                <p>Se agregará a la lista sin salir de la cuenta</p>
            </div>
            <button type="button" class="modal-close btn-close-banco-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="banco-rapido-form" novalidate>
                <input type="hidden" name="btn_nuevo_banco" value="1">
                <div class="form-field">
                    <label class="form-label" for="banco-rapido-id">Código del Banco <span class="required">*</span></label>
                    <input type="text" id="banco-rapido-id" name="txt_banco_id" class="form-input" placeholder="Ej: 0001234" minlength="6" maxlength="10">
                    <span class="field-error" id="err-banco-id"></span>
                </div>
                <div class="form-field">
                    <label class="form-label" for="banco-rapido-nombre">Nombre del Banco <span class="required">*</span></label>
                    <input type="text" id="banco-rapido-nombre" name="txt_banco_nombre" class="form-input" placeholder="Ej: Bancolombia" minlength="4" maxlength="50">
                    <span class="field-error" id="err-banco-nombre"></span>
                    <p class="field-hint">El banco se crea en estado Activo y queda seleccionado en la cuenta.</p>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-banco-modal">Cancelar</button>
            <button type="button" id="banco-rapido-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Banco</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR CUENTA -->
<div id="modal-edit-cuenta" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header blue">
            <div>
                <h2>Editar Cuenta Bancaria</h2>
                <p>Modifique el banco o el tipo de cuenta</p>
            </div>
            <button class="modal-close btn-close-edit-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-cuenta-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id_empresa" id="edit-id-empresa-hid" value="">
                <input type="hidden" name="hid_edit_cta_empresa" id="edit-cta-empresa-hid" value="">
                <div class="form-field">
                    <label class="form-label">NIT de la Empresa</label>
                    <input type="text" id="edit-id-empresa-display" class="form-input" disabled>
                </div>
                <div class="form-field">
                    <label class="form-label">Número de Cuenta</label>
                    <input type="text" id="edit-cta-empresa-display" class="form-input" disabled>
                </div>
                <div class="form-field">
                    <label class="form-label">Banco <span class="required">*</span></label>
                    <select id="edit-id-banco" name="sel_edit_id_banco" class="form-select">
                        <option value="">Seleccione...</option>
                        <?php foreach ($bancos as $b): ?>
                            <option value="<?= htmlspecialchars($b['id_banco']) ?>"><?= htmlspecialchars($b['nom_banco']) ?></option>
                        <?php endforeach; ?>
                    </select>
                    <span class="field-error" id="err-edit-banco"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Tipo de Cuenta</label>
                    <select id="edit-tipocuenta" name="sel_edit_tipocuenta" class="form-select">
                        <option value="false">Ahorros</option>
                        <option value="true">Corriente</option>
                    </select>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Actualizar Cuenta</button>
        </div>
    </div>
</div>

<!-- MODAL: CONFIRMAR ELIMINACIÓN (estilo módulo Compras) -->
<div id="modal-confirm-eliminar" class="modal-overlay hidden">
    <div class="modal-box confirm-box">
        <div class="confirm-icon"><i class="fas fa-exclamation-triangle"></i></div>
        <h4 id="confirm-eliminar-title"></h4>
        <p id="confirm-eliminar-body"></p>
        <div class="confirm-buttons">
            <button type="button" class="btn-cancelar" id="confirm-eliminar-cancel-btn">Cancelar</button>
            <button type="button" class="btn-eliminar" id="confirm-eliminar-ok-btn">Sí, eliminar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<!-- SCRIPTS JS -->
<script src="modules/tescxp/js/ctas_empresa.js"></script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
