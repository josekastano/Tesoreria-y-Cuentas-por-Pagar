DROP TABLE IF EXISTS tab_pagos_cxp;
DROP TABLE IF EXISTS tab_motivos_rechazo;
DROP TABLE IF EXISTS tab_det_archivo_plano;
DROP TABLE IF EXISTS tab_enc_archivo_plano;
DROP TABLE IF EXISTS tab_tipos_pago;
DROP TABLE IF EXISTS tab_det_cronopagos;
DROP TABLE IF EXISTS tab_enc_cronopagos;
DROP TABLE IF EXISTS tab_cuotasxfactura;
DROP TABLE IF EXISTS tab_cuentasxpagar;
DROP TABLE IF EXISTS tab_bancoxprov;
DROP TABLE IF EXISTS tab_ctas_empresa;
DROP TABLE IF EXISTS tab_det_caja_menor;
DROP TABLE IF EXISTS tab_enc_caja_menor;
DROP TABLE IF EXISTS tab_festivos;
DROP TABLE IF EXISTS tab_pmtros_tescxp;


----------------------------------------------
-- MÓDULO DE TESORERIA
----------------------------------------------
--------------------------------------------
-- TABLA DE PARÁMETROS DE TESORERÍA Y CXP --
--------------------------------------------
-- TABLA 1: Parámetros de Tesorería
CREATE TABLE tab_pmtros_tescxp
(
    id_empresa	        VARCHAR(10)		    NOT NULL,													                                    -- Identificador de la empresa
    fec_diapago1        DECIMAL(1,0)        NOT NULL CHECK((fec_diapago1) >= 1 AND (fec_diapago1) <= 6) DEFAULT 1,                          -- Día #1 en el que la empresa decide pagar
    fec_diapago2        DECIMAL(1,0)        NOT NULL CHECK((fec_diapago2) >= 1 AND (fec_diapago2) <= 6) DEFAULT 3,                          -- Día #2 en el que la empresa decide pagar
    fec_diapago3        DECIMAL(1,0)        NOT NULL CHECK((fec_diapago3) >= 1 AND (fec_diapago3) <= 6) DEFAULT 5,                          -- Día #3 en el que la empresa decide pagar
    val_min_reembolso   DECIMAL(8,0)        NOT NULL CHECK((val_min_reembolso >= 0) AND (val_min_reembolso <= 99999999)) DEFAULT 0,         -- Valor mínimo de reembolso para crear otra caja menor
    ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY         (id_empresa),
    FOREIGN KEY         (id_empresa)        REFERENCES tab_pmtros_grales(id_empresa)                                                                                                   
);

-----------------------
-- TABLA DE FESTIVOS --
-----------------------
-- TABLA 2: Días festivos
CREATE TABLE tab_festivos
(
    id_festivo         DECIMAL(4,0)         NOT NULL CHECK((id_festivo >= 0 AND id_festivo <= 9999)),                                                   -- Identificador del día festivo
    fecha              DATE                 NOT NULL DEFAULT CURRENT_DATE,                                                                              -- Fecha de el día festivo (no se restringe a futuro: debe poder cargarse el calendario completo del año)
    nom_festivo        VARCHAR(50)          NOT NULL CHECK((LENGTH(nom_festivo) >= 3) AND (LENGTH(nom_festivo) <= 50)) DEFAULT 'Día sin especificar',   -- Nombre descriptivo
    ind_borrado        BOOLEAN              NOT NULL DEFAULT FALSE,                   										                            -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo
     
    PRIMARY KEY (id_festivo)
);

-------------------------
-- TABLA DE CAJA MENOR --
-------------------------
-- TABLA 3: Cajas Menores (fondos fijos asignados)
CREATE TABLE tab_enc_caja_menor
(
    id_caja_menor 		DECIMAL(10,0)		NOT NULL CHECK(id_caja_menor > 0 AND id_caja_menor <= 9999999999),				                    -- ID de caja (hasta 9,999,999,999)
    nom_caja_menor 		VARCHAR(50) 		NOT NULL CHECK(LENGTH(nom_caja_menor) >= 3 AND LENGTH(nom_caja_menor) <= 50) DEFAULT 'Caja Menor',  -- Nombre descriptivo
    monto_asignado 		DECIMAL(8,0) 		NOT NULL CHECK(monto_asignado >= 0 AND monto_asignado <= 99999999) DEFAULT 0,				        -- Fondo fijo asignado
    monto_disponible 	DECIMAL(8,0) 		NOT NULL CHECK(monto_disponible >= 0 AND monto_disponible <= 99999999),			                    -- Saldo disponible
    fecha_apertura 		DATE 				NOT NULL DEFAULT CURRENT_DATE,                                      								-- Fecha de creación (la app valida que no sea futura al abrir la caja)
    fecha_cierre 		DATE,																									                -- Fecha de cierre (NULL si está activa)
    ind_estado_caja_m 	BOOLEAN 			NOT NULL DEFAULT TRUE,																                -- TRUE = Activa / FALSE = Cerrada
	ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo
	
    PRIMARY KEY         (id_caja_menor),
	
    CONSTRAINT chk_caja_fechas              CHECK(fecha_cierre IS NULL OR fecha_cierre >= fecha_apertura),
    CONSTRAINT chk_caja_disponible          CHECK(monto_disponible <= monto_asignado)
);

----------------------------------------
-- TABLA DE MOVIMIENTOS DE CAJA MENOR --
----------------------------------------
-- TABLA 4: Movimientos de Caja Menor (ingresos y egresos)
CREATE TABLE tab_det_caja_menor
(
    id_caja_menor 		DECIMAL(10,0) 		NOT NULL CHECK(id_caja_menor > 0 AND id_caja_menor <= 9999999999),                          -- ID de caja (hasta 9,999,999,999)
    id_movimiento 		DECIMAL(10,0) 		NOT NULL CHECK(id_movimiento > 0 AND id_movimiento <= 9999999999),                          -- ID del movimiento hecho en la caja
    concepto 			VARCHAR(200) 		NOT NULL CHECK(LENGTH(concepto) > 0 AND LENGTH(concepto) <= 200) DEFAULT 'Sin especificar', -- Descripción del movimiento
    val_movimiento 		DECIMAL(8,0) 		NOT NULL CHECK(val_movimiento >= 1 AND val_movimiento <= 99999999) DEFAULT 1,               -- Valor del movimiento
    fecha_movimiento 	DATE 				NOT NULL DEFAULT CURRENT_DATE,                                                              -- Fecha del movimiento (se permite registro retroactivo: el soporte llega después del gasto)
    ind_estado 			DECIMAL(1,0) 		NOT NULL DEFAULT 1 CHECK((ind_estado >= 1) AND (ind_estado <= 3)),                          -- 1 = Pendiente, 2 = Aprobado, 3 = Reembolsado

    PRIMARY KEY         (id_caja_menor, id_movimiento),
    FOREIGN KEY         (id_caja_menor)     REFERENCES tab_enc_caja_menor(id_caja_menor)
);
-- Consultas tipo: "fecha es la que se realizó un movimiento en la caja menor"
CREATE INDEX IF NOT EXISTS idx_mov_caja_fecha ON tab_det_caja_menor(fecha_movimiento);

-- Consultas tipo: "movimientos que se hayan realizado en una caja menor en específico"
CREATE INDEX IF NOT EXISTS idx_mov_caja_caja ON tab_det_caja_menor(id_caja_menor);

------------------------------------
-- TABLA DE CUENTAS DE LA EMPRESA --
------------------------------------
-- TABLA 5: Cuentas de la empresa
CREATE TABLE tab_ctas_empresa
(
    id_empresa	        VARCHAR(10)		    NOT NULL,													                                    -- Identificador de la empresa                                              -- Identificador (NIT) de la empresa
    cta_empresa         VARCHAR(16)         NOT NULL CHECK(LENGTH(cta_empresa) >= 10 AND LENGTH(cta_empresa) <= 16) DEFAULT '0000000000',   -- Número de cuenta bancaria de la empresa
    id_banco            VARCHAR             NOT NULL,                                                                                           -- Identificador del banco
    ind_tipocuenta      BOOLEAN             NOT NULL DEFAULT FALSE,                                                                         -- TRUE = Corriente / FALSE = Ahorros
    ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY         (id_empresa,cta_empresa),         
    FOREIGN KEY         (id_empresa)        REFERENCES tab_pmtros_grales(id_empresa),   
    FOREIGN KEY         (id_banco)          REFERENCES tab_bancos(id_banco)                                                                             
);

--------------------------------------------------
--        TABLA DE BANCOS POR PROVEEDORES       --
--------------------------------------------------
-- TABLA 6: Tabla de bancos por proveedores
CREATE TABLE IF NOT EXISTS tab_bancoxprov
(
    id_proveedor        VARCHAR(10)         NOT NULL CHECK(id_proveedor ~ '^[1-9][0-9]{7,9}$') DEFAULT '2222222222',                            -- Identificador (NIT) del proveedor
    cta_proveedor       VARCHAR(16)         NOT NULL CHECK(LENGTH(cta_proveedor) >= 10 AND LENGTH(cta_proveedor) <= 16) DEFAULT '0000000000',   -- Número de cuenta bancaria del proveedor
    id_banco            VARCHAR             NOT NULL,                                                                                           -- Identificador del banco 
    ind_tipocuenta      BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Corriente / FALSE = Ahorros
    ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY         (id_proveedor,cta_proveedor),                                                                                 
    FOREIGN KEY         (id_proveedor)      REFERENCES tab_proveedores(id_proveedor),
    FOREIGN KEY         (id_banco)          REFERENCES tab_bancos(id_banco)
);

--------------------------------
-- TABLA DE CUENTAS POR PAGAR --
--------------------------------
-- TABLA 7: Tabla de Cuentas por pagar
CREATE TABLE tab_cuentasxpagar
(
    id_factura          DECIMAL(8,0)        NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                                     -- Identificador de la factura
    id_proveedor        VARCHAR(10)         NOT NULL CHECK(id_proveedor ~ '^[1-9][0-9]{7,9}$') DEFAULT '2222222222',                            -- Identificador (NIT) del proveedor
    id_ordencompra      DECIMAL(6,0)            NULL CHECK (id_ordencompra IS NULL OR id_ordencompra > 0),                                                                 -- Identificador de la orden de compra
    fec_emision         DATE                NOT NULL DEFAULT CURRENT_DATE,                                                                      -- Fecha de emisión de la factura
    fec_vencimiento     DATE                NOT NULL CHECK (fec_vencimiento > fec_emision),                                                     -- FECHA DE PAGO FACTURA (FECHA EMISIÓN + DIAS DE PAGO)
    val_factura         DECIMAL(10,0)       NOT NULL CHECK((val_factura) >= 0 AND (val_factura) <= 9999999999),                                 -- Monto total de la factura
    val_saldo           DECIMAL(10,0)       NOT NULL CHECK((val_saldo >= 0) AND (val_saldo <= 9999999999)),                                     -- Valor restante para terminar de pagar la factura
    num_cuotas          DECIMAL(2,0)        NOT NULL CHECK((num_cuotas) >= 1 AND (num_cuotas) <= 99),                                           -- Número de cuotas totales en las que se acordó la factura
    ind_estado          BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Pagado O FALSE = En deuda

    PRIMARY KEY         (id_factura),                                                                                           
    FOREIGN KEY         (id_proveedor)      REFERENCES tab_proveedores(id_proveedor),
    FOREIGN KEY         (id_ordencompra)    REFERENCES tab_enc_ordcomp(id_ordencompra)  
);
-- Consultas tipo: "facturas pendientes de un proveedor"
CREATE INDEX idx_facturas_proveedor         ON tab_cuentasxpagar(id_proveedor);

-- Consultas tipo: "facturas vencidas hoy"
CREATE INDEX idx_facturas_vencimiento       ON tab_cuentasxpagar(fec_vencimiento);

-- Consultas tipo: "todas las facturas pendientes"
CREATE INDEX idx_facturas_estado            ON tab_cuentasxpagar(ind_estado);

------------------------------
-- TABLA DE CUOTAS FACTURAS --
------------------------------
-- TABLA 8: Tabla de cuotas por facturas
CREATE TABLE tab_cuotasxfactura
(
    id_factura          DECIMAL(8,0)        NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                     -- Identificador de la factura
    id_cuota            DECIMAL(2,0)        NOT NULL CHECK((id_cuota) >= 1 AND (id_cuota) <= 99),                               -- Número de cuota de la factura
    fec_vencimiento     DATE 				NOT NULL,                                                                           -- Fecha en la que vence cada cuota
    val_cuota           DECIMAL(10,0)       NOT NULL CHECK((val_cuota) >= 0 AND (val_cuota) <= 9999999999),                     -- Monto total de la factura
    ind_pagada          BOOLEAN             NOT NULL DEFAULT FALSE,                                                             -- TRUE = Pagado / FALSE = Pendiente

    PRIMARY KEY(id_factura,id_cuota),
    FOREIGN KEY(id_factura)                 REFERENCES tab_cuentasxpagar(id_factura)  
);
-- Consultas tipo: "cuotas pendientes de esta factura"
CREATE INDEX idx_cuotas_pagada ON tab_cuotasxfactura(ind_pagada);

-- Consultas tipo: "cuotas que vencen esta semana"
CREATE INDEX idx_cuotas_vencimiento ON tab_cuotasxfactura(fec_vencimiento);

------------------------------------------------
-- TABLA DE ENCABEZADO DE CRONOGRAMA DE PAGOS --
------------------------------------------------
-- TABLA 9: Tabla de encabezado cronograma de pagos
CREATE TABLE tab_enc_cronopagos
(
    id_cronograma       DECIMAL(10,0) 		NOT NULL CHECK((id_cronograma) >= 0 AND (id_cronograma) <= 9999999999),             -- Identificador del cronograma
    nom_cronograma      VARCHAR(30)         NOT NULL CHECK(LENGTH(nom_cronograma) >= 3 AND (LENGTH(nom_cronograma) <= 30)) DEFAULT 'Cronograma de pago',   -- Nombre del cronograma de pago
    fec_programacion    DATE                NOT NULL,                                                                           -- Fecha para la cual se planificó pagar dicho cronograma (la app valida que sea futura al crearlo)
    total_a_pagar       DECIMAL(10,0)       NOT NULL CHECK((total_a_pagar) >= 0 AND (total_a_pagar) <= 9999999999),             -- Monto total a pagar por ese cronograma
    ind_estado          BOOLEAN             NOT NULL DEFAULT FALSE,                                                             -- TRUE = Pagado / FALSE = Pendiente
	ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                             -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY(id_cronograma)
);
-- Consultas tipo: "fecha en las que se va a realizar un cronograma"
CREATE INDEX idx_crono_fec_prog ON tab_enc_cronopagos(fec_programacion);

-- Consultas tipo: "cronogramas pendientes o pagados"
CREATE INDEX idx_crono_estado   ON tab_enc_cronopagos(ind_estado);

---------------------------------------------
-- TABLA DE DETALLE DE CRONOGRAMA DE PAGOS --
---------------------------------------------
-- TABLA 10: Tabla de detalle de cronograma de pagos
CREATE TABLE tab_det_cronopagos
(
    id_cronograma       DECIMAL(10,0) 		NOT NULL CHECK((id_cronograma) >= 0 AND (id_cronograma) <= 9999999999),             						   -- Identificador del cronograma
	id_factura          DECIMAL(8,0)        NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                     						   -- Identificador de la factura
    id_cuota            DECIMAL(2,0)        NOT NULL CHECK((id_cuota) >= 1 AND (id_cuota) <= 99),                              						       -- Número de cuota que se va a pagar en el cronograma
    val_a_pagar         DECIMAL(10,0)       NOT NULL CHECK((val_a_pagar) >= 0 AND (val_a_pagar) <= 9999999999),                                            -- Monto a pagar por cada cuota factura

    PRIMARY KEY(id_cronograma,id_factura,id_cuota),
    FOREIGN KEY(id_cronograma)              REFERENCES tab_enc_cronopagos(id_cronograma),
    FOREIGN KEY(id_factura,id_cuota)        REFERENCES tab_cuotasxfactura(id_factura,id_cuota),

    CONSTRAINT uq_cuota_programada          UNIQUE (id_factura,id_cuota)                                                        -- Una cuota solo puede estar programada en UN cronograma a la vez (impide el doble pago)
);

---------------------------------------------
-- TABLA DE TIPOS DE PAGO                  --
---------------------------------------------
-- TABLA 11: Tabla de tipos de pago
CREATE TABLE tab_tipos_pago 
(
    id_tipo_pago        DECIMAL(1,0) NOT NULL CHECK((id_tipo_pago) >= 1 AND (id_tipo_pago) < 10),
    nom_tipo_pago       VARCHAR(15)  NOT NULL CHECK(LENGTH(nom_tipo_pago) >= 1 AND LENGTH(nom_tipo_pago) <= 15),                     -- Nombre del tipo de pago (PROVEEDORES, NÓMINA U OTRO)
    ind_borrado         BOOLEAN      NOT NULL DEFAULT FALSE,                                                                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY(id_tipo_pago)
);

------------------------------------------
-- TABLA DE ENCABEZADO DE ARCHIVO PLANO --
------------------------------------------
-- TABLA 12: Tabla de encabezado de archivo plano
CREATE TABLE tab_enc_archivo_plano 
(
    id_archivo_plano      DECIMAL(10,0) NOT NULL CHECK((id_archivo_plano) >= 0 AND (id_archivo_plano) <= 9999999999),                       -- Identificador del archivo plano
    nom_archivo           VARCHAR(30)         NOT NULL CHECK(LENGTH(nom_archivo) >= 3 AND (LENGTH(nom_archivo) <= 30)) DEFAULT 'archivo_plano',   -- Nombre del archivo plano
    id_empresa	          VARCHAR(10)	NOT NULL,													                                        -- Identificador de la empresa
    nom_empresa	          VARCHAR       NOT NULL CHECK(LENGTH(nom_empresa) >= 5 AND LENGTH(nom_empresa) <= 60),                             -- Nombre de la empresa
    id_banco              VARCHAR       NOT NULL,                                                                                           -- Identificador del banco
    ind_tipocuenta        BOOLEAN       NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Corriente / FALSE = Ahorros
    cta_empresa           VARCHAR(16)   NOT NULL CHECK(LENGTH(cta_empresa) >= 10 AND LENGTH(cta_empresa) <= 16),                            -- Número de cuenta bancaria de la empresa de la cuál va a salir el dinero
    fecha_aplicacion      DATE          NOT NULL DEFAULT CURRENT_DATE,
    id_tipo_pago          DECIMAL(1,0) NOT NULL CHECK((id_tipo_pago) >= 1 AND (id_tipo_pago) < 10),
    fec_generacion        DATE,                                                                                                             -- Fecha de generación del archivo(NULL Si no se ha creado)
    ind_generado          BOOLEAN       NOT NULL DEFAULT FALSE,                                                                             -- Indicador de generado del archivo

    PRIMARY KEY(id_archivo_plano),
    FOREIGN KEY(id_empresa,cta_empresa)     REFERENCES tab_ctas_empresa(id_empresa,cta_empresa),
    FOREIGN KEY(id_banco)                   REFERENCES tab_bancos(id_banco),
    FOREIGN KEY(id_tipo_pago)               REFERENCES tab_tipos_pago(id_tipo_pago)
);
-- Consultas tipo: "archivos planos que se hayan generado o no"
CREATE INDEX idx_archplano_generado ON tab_enc_archivo_plano(ind_generado);

------------------------------------
-- TABLA DE DETALLE ARCHIVO PLANO --
------------------------------------
-- TABLA 13: Tabla de detalle de archivo plano
CREATE TABLE tab_det_archivo_plano 
(
    id_archivo_plano            DECIMAL(10,0)  NOT NULL CHECK((id_archivo_plano) >= 0 AND (id_archivo_plano) <= 9999999999),    -- Identificador del archivo plano
    id_cronograma               DECIMAL(10,0)  NOT NULL CHECK((id_cronograma) >= 0 AND (id_cronograma) <= 9999999999),          -- Identificador del cronograma
    id_factura                  DECIMAL(8,0)   NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                  -- Identificador de la factura
    id_cuota                    DECIMAL(2,0)   NOT NULL CHECK((id_cuota) >= 1 AND (id_cuota) <= 99),                            -- Número de cuota que se va a pagar en el cronograma
    -- ID FACTURA E ID CUOTA NO SE VE REFLEJADO EN EL ARCHIVO PLANO PORQUE AL BANCO NO LE INTERESA SABER ESTO PARA PAGAR, SOLO ESTÁ AGREGADO
    -- PODER TENER EL CONTROL DE LAS FACTURAS AÑADIDAS AL ARCHIVO PLANO.

    id_tipo        		        VARCHAR(5)     NOT NULL CHECK(id_tipo ~ '^[A-Z]{2,5}$'),                                   --  tipo de documento
    id_proveedor                VARCHAR(10)    NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                                                               -- Identificador del proveedor (ID empresa)
    nom_tercero			        VARCHAR	       NOT NULL CHECK(LENGTH(nom_tercero) >= 4 AND LENGTH(nom_tercero) <= 50),	    --  nombre del tercero
    id_banco                    VARCHAR        NOT NULL,                                                                                           -- Identificador del banco
    ind_tipocuenta              BOOLEAN        NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Corriente / FALSE = Ahorros
    cta_proveedor               VARCHAR(16)    NOT NULL CHECK(LENGTH(cta_proveedor) >= 10 AND LENGTH(cta_proveedor) <= 16),   -- Número de cuenta de destino para pagar
    val_a_pagar                 NUMERIC(10,0)  NOT NULL CHECK((val_a_pagar) > 0 ),  
    concepto                    VARCHAR(80),

    PRIMARY KEY(id_archivo_plano,id_cronograma,id_factura,id_cuota),
    FOREIGN KEY(id_archivo_plano)                   REFERENCES tab_enc_archivo_plano(id_archivo_plano),
    FOREIGN KEY(id_cronograma,id_factura,id_cuota)  REFERENCES tab_det_cronopagos(id_cronograma,id_factura,id_cuota),
    FOREIGN KEY(id_proveedor,cta_proveedor)         REFERENCES tab_bancoxprov(id_proveedor,cta_proveedor),
    FOREIGN KEY(id_banco)                           REFERENCES tab_bancos(id_banco),

    CONSTRAINT uq_cuota_en_archivo UNIQUE (id_factura, id_cuota)
);

-------------------------------------
-- TABLA DE MOTIVOS DE RECHAZO     --
-------------------------------------
-- TABLA 14: Catálogo de motivos. Lo usa tab_pagos
-- ind_borrado permite dar de baja un motivo sin romper los registros históricos.
CREATE TABLE tab_motivos_rechazo
(
    id_motivo_rechazo       DECIMAL(3,0) NOT NULL CHECK(id_motivo_rechazo >= 1 AND id_motivo_rechazo <= 999),   -- Identificador del motivo
    des_motivo              VARCHAR(100) NOT NULL CHECK(LENGTH(des_motivo) >= 3),               -- Descripción del motivo
    cod_bancario            VARCHAR(10),                                                        -- Código que devuelve el banco, si lo hay
    ind_borrado             BOOLEAN      NOT NULL DEFAULT FALSE,                                -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY (id_motivo_rechazo)
);

-----------------------
-- TABLA DE PAGOS    --
-----------------------
-- TABLA 15: registra cada intento de pago de una CUOTA DE FACTURA (aprobado o
-- rechazado). 
-- Nunca se borra un intento rechazado.
-- Alcance: aquí van únicamente los pagos de cuotas. Caja menor y sus
-- reembolsos NO entran a esta tabla (ver tab_det_caja_menor y
-- tab_reembolsos_caja).
-- Nota: sin trigger, marcar la cuota como pagada y descontar el saldo de la
-- factura al aprobar un pago queda a cargo de la aplicación.
CREATE TABLE tab_pagos_cxp
(
    id_pago             DECIMAL(10,0) NOT NULL CHECK(id_pago >= 1 AND id_pago <= 9999999999),
    id_factura          DECIMAL(8,0)  NOT NULL,
    id_cuota            DECIMAL(2,0)  NOT NULL,
    id_archivo_plano    DECIMAL(10,0) NOT NULL,
    fec_pago            DATE          NOT NULL DEFAULT CURRENT_DATE,                                    -- un pago se registra cuando ya ocurrió; la app valida que no sea futura al registrarlo
    val_pago            DECIMAL(10,0) NOT NULL CHECK(val_pago > 0 AND val_pago <= 9999999999),
    estado_pago         VARCHAR(10)   NOT NULL DEFAULT 'PENDIENTE' CHECK(estado_pago IN ('PENDIENTE','APROBADO','RECHAZADO')),
    id_motivo_rechazo   DECIMAL(3,0),                                                                   -- Obligatorio si el estado es RECHAZADO

    PRIMARY KEY (id_pago),
    FOREIGN KEY (id_factura, id_cuota)                   REFERENCES tab_cuotasxfactura(id_factura, id_cuota),
    FOREIGN KEY (id_archivo_plano, id_factura, id_cuota) REFERENCES tab_det_archivo_plano(id_archivo_plano,id_cronograma,id_factura,id_cuota),
    FOREIGN KEY (id_motivo_rechazo)                      REFERENCES tab_motivos_rechazo(id_motivo_rechazo)
);
-- Una cuota solo puede tener UN pago APROBADO. El índice es parcial a propósito:
-- los intentos RECHAZADOS no cuentan, así una cuota se puede reintentar las veces
-- que haga falta, pero aprobarse una sola vez.
CREATE UNIQUE INDEX uq_pago_aprobado_cuota ON tab_pagos_cxp(id_factura, id_cuota) WHERE estado_pago = 'APROBADO';
