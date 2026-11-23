<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Parámetros de Tesorería";
$page_description = "Configuración general de días de pago y reembolsos de caja menor";
$page_icon        = "bi-sliders";
$page_extra_css   = ['modules/tescxp/css/tcx_pantalla.css', 'modules/tescxp/css/pmtros_tescxp.css'];
$page_extra_js    = ['modules/tescxp/js/pmtros_tescxp.js'];
$page_erp_ui      = ['botones'];   // GUIA_PANTALLAS_ERP §2: solo lo que usa (sin lista ni modales)
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
$pmtros_grales = $list_pmtros_grales->fetch(PDO::FETCH_ASSOC);
$id_empresa_fijo = $pmtros_grales['id_empresa'] ?? '';

// ============================================================
// DÍAS DE LA SEMANA VÁLIDOS PARA PAGO (1=Lunes ... 6=Sábado)
// ============================================================
const DIAS_SEMANA = [
    1 => 'Lunes',
    2 => 'Martes',
    3 => 'Miércoles',
    4 => 'Jueves',
    5 => 'Viernes',
    6 => 'Sábado',
];

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    erp_validar_csrf();   // SEC-08: token de la sesión + origen
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- GUARDAR PARÁMETROS (INSERT o UPDATE según exista) ----------
        if (isset($_POST['btn_guardar'])) {
            $fec_diapago1       = (int)($_POST['sel_diapago1']         ?? 0);
            $fec_diapago2       = (int)($_POST['sel_diapago2']         ?? 0);
            $fec_diapago3       = (int)($_POST['sel_diapago3']         ?? 0);
            $val_min_reembolso  = (float)($_POST['txt_min_reembolso']  ?? 0);
            $existe             = ($_POST['hid_existe']                ?? '0') === '1';

            $errores = [];

            if (empty($id_empresa_fijo)) {
                $errores['err-id-empresa'] = 'No se encontró el NIT de la empresa en Parámetros Generales. Configure primero ese módulo.';
            }
            if ($fec_diapago1 < 1 || $fec_diapago1 > 6) {
                $errores['err-diapago1'] = 'Seleccione un día válido (Lunes a Sábado).';
            }
            if ($fec_diapago2 < 1 || $fec_diapago2 > 6) {
                $errores['err-diapago2'] = 'Seleccione un día válido (Lunes a Sábado).';
            }
            if ($fec_diapago3 < 1 || $fec_diapago3 > 6) {
                $errores['err-diapago3'] = 'Seleccione un día válido (Lunes a Sábado).';
            }
            if (!empty($fec_diapago1) && !empty($fec_diapago2) && !empty($fec_diapago3)) {
                $dias = [$fec_diapago1, $fec_diapago2, $fec_diapago3];
                if (count($dias) !== count(array_unique($dias))) {
                    $errores['err-diapago3'] = 'Los tres días de pago deben ser diferentes entre sí.';
                }
            }
            if ($val_min_reembolso < 0 || $val_min_reembolso > 99999999) {
                $errores['err-min-reembolso'] = 'El valor mínimo de reembolso debe estar entre 0 y 99.999.999.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $params = [
                ':wid_empresa'        => $id_empresa_fijo,
                ':wfec_diapago1'      => $fec_diapago1,
                ':wfec_diapago2'      => $fec_diapago2,
                ':wfec_diapago3'      => $fec_diapago3,
                ':wval_min_reembolso' => $val_min_reembolso,
            ];

            if ($existe) {
                $upd_pmtros_tescxp->execute($params);
                $respuesta['message'] = 'Parámetros actualizados correctamente.';
            } else {
                $ins_pmtros_tescxp->execute($params);
                $respuesta['message'] = 'Parámetros guardados correctamente.';
            }

            $respuesta['success'] = true;
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
        $respuesta['message'] = $mensaje;
        echo json_encode($respuesta);
        exit;
    }
}

// ============================================================
// CARGAR PARÁMETROS ACTUALES (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_pmtros_tescxp->execute();
$pmtros = $list_pmtros_tescxp->fetch(PDO::FETCH_ASSOC);
$existe_pmtros = $pmtros !== false;

$dias_sel = array_values(array_filter([
    (int)($pmtros['fec_diapago1'] ?? 0),
    (int)($pmtros['fec_diapago2'] ?? 0),
    (int)($pmtros['fec_diapago3'] ?? 0),
]));

$dias_definidos = count($dias_sel);

$dias_nombres = $dias_definidos
    ? implode(' · ', array_map(fn($n) => DIAS_SEMANA[$n] ?? '', $dias_sel))
    : 'Sin definir';

$min_reembolso_val = (float)($pmtros['val_min_reembolso'] ?? 0);

// Razón social (si Parámetros Generales la expone)
$nom_empresa = $pmtros_grales['nom_empresa']
    ?? $pmtros_grales['des_empresa']
    ?? $pmtros_grales['nombre_empresa']
    ?? '';

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<div id="mod-pmtros-tescxp" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Parámetros de Tesorería</h1>
            <p>Días de pago a proveedores y monto mínimo de reembolso de caja menor</p>
        </div>
    </div>

    <?php if (empty($id_empresa_fijo)): ?>

        <!-- SIN EMPRESA CONFIGURADA -->
        <div class="table-container">
            <div class="empty-state">
                <i class="fas fa-building"></i>
                <p>No hay una empresa registrada</p>
                <span>Configure la empresa en Parámetros Generales antes de definir estos parámetros</span>
            </div>
        </div>

    <?php else: ?>

    <div class="pmt-pg">

        <!-- ================= PANEL IZQUIERDO: RESUMEN ================= -->
        <div class="pmt-panel-l">
            <div class="pmt-cc">

                <div class="pmt-cc-top">
                    <span class="pmt-badge-act">Empresa activa</span>
                </div>

                <div class="pmt-cc-body">
                    <div class="pmt-cc-nit">NIT <?= htmlspecialchars($id_empresa_fijo) ?></div>
                    <div class="pmt-cc-name"><?= htmlspecialchars($nom_empresa !== '' ? $nom_empresa : 'Empresa registrada') ?></div>

                    <div class="pmt-cc-stats">

                        <div class="pmt-cc-stat">
                            <div class="pmt-cc-stat-label">Días de pago</div>
                            <div class="pmt-cc-stat-value" id="kpi-dias"><?= $dias_definidos ?>/3</div>
                        </div>

                        <div class="pmt-cc-stat">
                            <div class="pmt-cc-stat-label">Estado</div>
                            <div class="pmt-cc-status <?= $existe_pmtros ? 'ok' : 'pend' ?>">
                                <span class="pmt-cc-status-ico <?= $existe_pmtros ? 'green' : 'amber' ?>" id="stat-estado-icon">
                                    <i class="fas <?= $existe_pmtros ? 'fa-check-circle' : 'fa-exclamation-triangle' ?>"></i>
                                </span>
                                <span id="kpi-estado"><?= $existe_pmtros ? 'Configurada' : 'Sin configurar' ?></span>
                            </div>
                        </div>

                        <div class="pmt-cc-stat pmt-cc-stat-wide">
                            <div class="pmt-cc-stat-label">Reembolso mínimo de caja menor</div>
                            <div class="pmt-cc-stat-value" id="kpi-reembolso">$<?= number_format($min_reembolso_val, 0, ',', '.') ?></div>
                        </div>

                        <div class="pmt-cc-stat pmt-cc-stat-wide">
                            <div class="pmt-cc-stat-label">Días programados</div>
                            <div class="pmt-cc-stat-days" id="kpi-dias-nombres"><?= htmlspecialchars($dias_nombres) ?></div>
                        </div>

                    </div>
                </div>

                <div class="pmt-cc-foot">
                    <div class="pmt-cc-meta">
                        <i class="fas fa-info-circle"></i>
                        <span>Los pagos a proveedores solo se programan en los días definidos aquí.</span>
                    </div>
                </div>

            </div>
        </div>

        <!-- ================= PANEL DERECHO: FORMULARIO ================= -->
        <div class="pmt-panel-r">

            <div class="pmt-cfg-header">
                <div class="pmt-cfg-icon"><i class="fas fa-sliders-h"></i></div>
                <h2 class="pmt-cfg-title">Configurar Parámetros</h2>
                <p class="pmt-cfg-sub">Parámetros de tesorería · NIT <?= htmlspecialchars($id_empresa_fijo) ?></p>
            </div>

            <div class="pmt-card">

                <form id="pmtros-form" novalidate>
                    <input type="hidden" name="btn_guardar" value="1">
                    <input type="hidden" name="hid_existe" id="hid-existe" value="<?= $existe_pmtros ? '1' : '0' ?>">

                    <div class="pmt-body">

                        <div class="pmt-fg">
                            <div class="week-head">
                                <span class="pmt-fl" id="lbl-dias">Días de pago programados <span class="required">*</span></span>
                                <span class="week-count" id="week-count"><?= $dias_definidos ?> de 3</span>
                            </div>

                            <div class="week-strip" id="week-strip" role="group" aria-labelledby="lbl-dias">
                                <?php
                                $dias_corto = [1 => 'L', 2 => 'M', 3 => 'M', 4 => 'J', 5 => 'V', 6 => 'S'];
                                foreach ($dias_corto as $num => $letra):
                                    $activo = in_array($num, $dias_sel);
                                ?>
                                    <button type="button"
                                            class="week-day <?= $activo ? 'active' : '' ?>"
                                            data-dia="<?= $num ?>"
                                            aria-pressed="<?= $activo ? 'true' : 'false' ?>">
                                        <span class="week-day-letter"><?= $letra ?></span>
                                        <span class="week-day-name"><?= DIAS_SEMANA[$num] ?></span>
                                    </button>
                                <?php endforeach; ?>
                            </div>

                            <!-- Valores que se envían al servidor (los llena el JS al hacer clic en los días) -->
                            <?php for ($i = 1; $i <= 3; $i++): ?>
                                <input type="hidden" id="diapago<?= $i ?>" name="sel_diapago<?= $i ?>"
                                       value="<?= !empty($pmtros['fec_diapago' . $i]) ? (int)$pmtros['fec_diapago' . $i] : '' ?>">
                            <?php endfor; ?>

                            <span class="field-error" id="err-dias"></span>
                            <p class="field-hint">Haga clic en un día para seleccionarlo o quitarlo. Debe elegir exactamente 3.</p>
                        </div>

                        <div class="pmt-fg">
                            <label class="pmt-fl" for="min-reembolso">Valor mínimo de reembolso de caja menor</label>
                            <div class="input-money">
                                <span class="money-prefix">$</span>
                                <input type="number" id="min-reembolso" name="txt_min_reembolso" class="form-input"
                                       placeholder="50000" min="0" max="99999999" step="1"
                                       value="<?= htmlspecialchars($pmtros['val_min_reembolso'] ?? '0') ?>">
                            </div>
                            <span class="field-error" id="err-min-reembolso"></span>
                            <p class="field-hint">Monto a partir del cual se habilita la creación de una nueva caja menor.</p>
                        </div>

                        <span class="field-error" id="err-id-empresa"></span>

                        <div class="pmt-hint">
                            <i class="fas fa-info-circle"></i>
                            <span>Seleccione los 3 días de la semana en los que la empresa programa sus pagos a proveedores. El NIT proviene de Parámetros Generales y no se modifica desde aquí.</span>
                        </div>

                    </div>
                </form>

                <div class="pmt-form-footer">
                    <div class="pmt-chg-ind" id="pmt-chg-ind">Cambios sin guardar</div>
                    <button type="button" class="btn btn-secondary" id="btn-reset-pmtros">Restablecer</button>
                    <button type="button" class="btn btn-primary" id="btn-guardar-pmtros" disabled>
                        <i class="fas fa-save"></i> Guardar cambios
                    </button>
                </div>

            </div>
        </div>

    </div>

    <?php endif; ?>

</div>

<!-- TOAST -->
<div id="toast" class="tcx-toast hidden" role="status" aria-live="polite">
    <i class="fas fa-check-circle"></i>
    <span id="toast-message"></span>
</div>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
