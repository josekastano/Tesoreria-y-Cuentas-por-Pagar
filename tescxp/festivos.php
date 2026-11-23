<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Festivos";
$page_description = "Gestión de días festivos para cálculo de fechas de pago";
$page_icon        = "bi-calendar-event";
$page_extra_css   = ['modules/tescxp/css/cmp_pantalla.css', 'modules/tescxp/css/festivos.css', 'modules/tescxp/css/cmp_modales.css'];
$page_extra_js    = ['modules/tescxp/js/festivos.js'];
$page_erp_ui      = ['modales', 'indicadores', 'filtros', 'paginador', 'lista_fija', 'movil', 'botones', 'orden'];   // GUIA_PANTALLAS_ERP §2
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    erp_validar_csrf();   // SEC-08: token de la sesión + origen
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- NUEVO FESTIVO ----------
        if (isset($_POST['btn_nuevo'])) {
            $fecha       = trim($_POST['txt_fecha']       ?? '');
            $nom_festivo = trim($_POST['txt_nom_festivo']  ?? '');

            $errores = [];

            $hoy = date('Y-m-d');
            if (empty($fecha)) {
                $errores['err-new-fecha'] = 'La fecha es obligatoria.';
            } elseif ($fecha < $hoy) {
                $errores['err-new-fecha'] = 'La fecha no puede ser anterior al día de hoy.';
            }
            if (strlen($nom_festivo) < 3 || strlen($nom_festivo) > 50) {
                $errores['err-new-nombre'] = 'El nombre debe tener entre 3 y 50 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $ins_festivo->execute([
                ':wfecha'       => $fecha,
                ':wnom_festivo' => $nom_festivo,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Festivo registrado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- EDITAR FESTIVO ----------
        if (isset($_POST['btn_editar'])) {
            $id_festivo  = (int)($_POST['hid_edit_id']        ?? 0);
            $fecha       = trim($_POST['txt_edit_fecha']      ?? '');
            $nom_festivo = trim($_POST['txt_edit_nom_festivo'] ?? '');

            $errores = [];

            $hoy = date('Y-m-d');
            if ($id_festivo <= 0) {
                $errores['err-edit-id'] = 'ID de festivo no válido.';
            }
            if (empty($fecha)) {
                $errores['err-edit-fecha'] = 'La fecha es obligatoria.';
            } elseif ($fecha < $hoy) {
                $errores['err-edit-fecha'] = 'La fecha no puede ser anterior al día de hoy.';
            }
            if (strlen($nom_festivo) < 3 || strlen($nom_festivo) > 50) {
                $errores['err-edit-nombre'] = 'El nombre debe tener entre 3 y 50 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $upd_festivo->execute([
                ':wid_festivo'  => $id_festivo,
                ':wfecha'       => $fecha,
                ':wnom_festivo' => $nom_festivo,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Festivo actualizado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- ELIMINAR FESTIVO ----------
        if (isset($_POST['btn_eliminar'])) {
            $id_festivo = (int)($_POST['hid_del_id'] ?? 0);
            if ($id_festivo <= 0) {
                throw new Exception('ID de festivo no válido.');
            }

            $del_festivo->execute([':wid_festivo' => $id_festivo]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Festivo eliminado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // Si no se reconoce ninguna acción
        $respuesta['message'] = 'Acción no válida.';
        echo json_encode($respuesta);
        exit;

    } catch (Exception $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        $mensaje = limpiar_error_pgsql($e->getMessage());
        if (empty($mensaje)) {
            $mensaje = $e->getMessage();
        }
        $respuesta['message'] = $mensaje;
        echo json_encode($respuesta);
        exit;
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_festivos->execute();
$festivos = $list_festivos->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>

<div id="mod-festivos" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Días Festivos</h1>
            <p>Gestión de festivos para el cálculo de fechas de pago</p>
        </div>
        <button id="btn-add-festivo" class="btn btn-primary">
            <i class="fas fa-plus"></i> Nuevo Festivo
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <?php
        $total      = count($festivos);
        $hoy        = date('Y-m-d');
        $proximo30  = strtotime('+30 days', strtotime($hoy));
        $proximos   = count(array_filter($festivos, fn($f) => strtotime($f['fecha']) >= strtotime($hoy) && strtotime($f['fecha']) <= $proximo30));
        $este_anio  = count(array_filter($festivos, fn($f) => substr($f['fecha'], 0, 4) === date('Y')));
        ?>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-calendar-day"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total</div>
                <div class="stat-value" id="stat-total"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-calendar-week"></i></div>
            <div class="stat-info">
                <div class="stat-label">Próximos 30 días</div>
                <div class="stat-value" id="stat-proximos"><?= $proximos ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-calendar-check"></i></div>
            <div class="stat-info">
                <div class="stat-label">Este año</div>
                <div class="stat-value" id="stat-anio"><?= $este_anio ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="festivo-search" class="search-input" placeholder="Buscar por nombre del festivo...">
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="festivos-page-size">Filas por página</label>
            <select id="festivos-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="festivos-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="festivos-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-id">
                <col class="col-fecha">
                <col class="col-nombre">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="number">ID <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="text">Fecha <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="2" data-sort-type="text">Nombre del Festivo <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="festivos-tbody">
            <?php if (empty($festivos)): ?>
                <tr class="empty-row">
                    <td colspan="4">
                        <div class="empty-state">
                            <i class="fas fa-calendar-times"></i>
                            <p>No hay festivos registrados</p>
                            <span>Haga clic en "Nuevo Festivo" para agregar el primero</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($festivos as $f):
                    $id_esc     = htmlspecialchars($f['id_festivo']);
                    $fecha_fmt  = htmlspecialchars(date('d/m/Y', strtotime($f['fecha'])));
                    $nombre_esc = htmlspecialchars($f['nom_festivo']);
                ?>
                <tr>
                    <td data-sort="<?= (int)$f['id_festivo'] ?>"><strong>#<?= $id_esc ?></strong></td>
                    <td data-sort="<?= htmlspecialchars(date('Y-m-d', strtotime($f['fecha']))) ?>"><?= $fecha_fmt ?></td>
                    <td data-sort="<?= $nombre_esc ?>"><?= $nombre_esc ?></td>
                    <td class="text-center">
                        <button class="btn-icon-sm edit" onclick='openEditModal(<?= json_encode($f) ?>)'>
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn-icon-sm reject" onclick="eliminarFestivo('<?= $id_esc ?>', '<?= htmlspecialchars($f['nom_festivo'], ENT_QUOTES) ?>')">
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
                <span class="pagination-range" id="festivos-range">0 de 0</span>
                <button type="button" id="festivos-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="festivos-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVO FESTIVO -->
<div id="modal-new-festivo" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header green">
            <div>
                <h2>Nuevo Festivo</h2>
                <p>Registre un nuevo día festivo</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-festivo-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label">Fecha <span class="required">*</span></label>
                    <input type="hidden" id="new-festivo-fecha" name="txt_fecha" value="">
                    <button type="button" class="form-input dp-trigger" id="new-festivo-fecha-btn" data-target="new-festivo-fecha" data-min="<?= date('Y-m-d') ?>">
                        <span class="dp-trigger-texto vacio">Seleccione una fecha</span>
                        <i class="fas fa-calendar-alt"></i>
                    </button>
                    <span class="field-error" id="err-new-fecha"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Nombre del Festivo <span class="required">*</span></label>
                    <input type="text" id="new-festivo-nombre" name="txt_nom_festivo" class="form-input" placeholder="Ej: Día de la Independencia" minlength="3" maxlength="50">
                    <span class="field-error" id="err-new-nombre"></span>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Festivo</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR FESTIVO -->
<div id="modal-edit-festivo" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header blue">
            <div>
                <h2>Editar Festivo</h2>
                <p>Modifique la información del festivo</p>
            </div>
            <button class="modal-close btn-close-edit-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-festivo-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id" id="edit-festivo-id" value="">
                <div class="form-field">
                    <label class="form-label">Fecha <span class="required">*</span></label>
                    <input type="hidden" id="edit-festivo-fecha" name="txt_edit_fecha" value="">
                    <button type="button" class="form-input dp-trigger" id="edit-festivo-fecha-btn" data-target="edit-festivo-fecha" data-min="<?= date('Y-m-d') ?>">
                        <span class="dp-trigger-texto vacio">Seleccione una fecha</span>
                        <i class="fas fa-calendar-alt"></i>
                    </button>
                    <span class="field-error" id="err-edit-fecha"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Nombre del Festivo <span class="required">*</span></label>
                    <input type="text" id="edit-festivo-nombre" name="txt_edit_nom_festivo" class="form-input" minlength="3" maxlength="50">
                    <span class="field-error" id="err-edit-nombre"></span>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Actualizar Festivo</button>
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

<!-- CALENDARIO FLOTANTE PARA ELEGIR FECHAS (mismo estilo que Cronograma de Pagos;
     aquí se puede elegir cualquier fecha — lo arma festivos.js) -->
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
        <span><i class="l-festivo"></i>Festivo ya registrado</span>
        <span><i class="l-hoy"></i>Hoy</span>
    </div>
    <div class="dp-acciones">
        <button type="button" class="dp-accion" id="dp-hoy">Hoy</button>
        <button type="button" class="dp-accion secundaria" id="dp-borrar">Borrar</button>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<!-- ============================================================
     DATOS PARA EL JS (variables globales)
     ============================================================ -->
<script>
const festivosData = <?= json_encode(array_values($festivos), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) ?>;
</script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
