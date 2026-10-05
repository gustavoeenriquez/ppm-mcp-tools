unit MCPTool.Conta.Catalog;

// GENERADO por gen_catalog.py desde uConServerMethods.pas + catalogo_modulos.json — no editar a mano.
// Catalogo de metodos publicos de ConServer agrupados en tools por dominio.

interface

type
  TContaMethodDef = record
    Name: string;      // operation (sin prefijo CON_)
    Doc: string;       // descripcion y params, tomados del fuente del servidor
    IsWrite: Boolean;  // True = modifica datos
  end;

  TContaModuleDef = record
    Tool: string;      // nombre del tool MCP
    Title: string;
    Desc: string;
    Methods: TArray<TContaMethodDef>;
  end;

function ContaModules: TArray<TContaModuleDef>;

implementation

function M(const AName, ADoc: string; AWrite: Boolean): TContaMethodDef;
begin
  Result.Name := AName;
  Result.Doc := ADoc;
  Result.IsWrite := AWrite;
end;

var
  GModules: TArray<TContaModuleDef>;

procedure BuildModules;
begin
  SetLength(GModules, 25);

  // Sistema y catalogos (19 ops)
  GModules[0].Tool := 'conta_sistema';
  GModules[0].Title := 'Sistema y catalogos';
  GModules[0].Desc := 'Version, perfil, catalogos globales (paises, monedas, NIIF, tipos de cuenta e identificacion), multi-empresa, auditoria, notificaciones in-app, favoritos y menu, tokens de agente y SSO';
  GModules[0].Methods := [
    M('GetVersion', '', False),
    M('GetMiPerfil', 'Retorna perfil del usuario autenticado (login, nombre, perfil, email, is_admin)', False),
    M('CrearTokenSSO', 'Emite un token de auto-delegacion para EL PROPIO usuario autenticado: va a con_agent_tokens con alcance ''lectura'' y vida corta, asi que la sesion resultante es de agente (is_admin=False, solo lecturas por la lista blanca) — abrir el ERP desde el HIS nunca escala privilegios. Una sesion de agente NO puede emitir (sin cadenas de refresco; regla C2 del contrato MakerAI intacta: esto no gestiona tokens de terceros). Params: { duracion_horas?: 1..24 (default 8), descripcion? } Returns: { token, login, nit_empresa, expira_en }', True),
    M('GetPaises', 'Retorna array de países disponibles', False),
    M('GetMonedas', 'Retorna array de monedas', False),
    M('GetGruposNIIF', 'Retorna grupos NIIF (1, 2, 3)', False),
    M('GetTiposCuenta', 'Retorna tipos de cuenta (ACTIVO, PASIVO, etc.)', False),
    M('GetTiposIdentificacion', 'Retorna tipos de identificación (NIT, CC, RFC, etc.) Params: { pais_codigo: string } — opcional, si vacío retorna todos', False),
    M('GetFavoritos', 'Devuelve el arreglo JSON de rutas del usuario, o [] si no tiene.', False),
    M('SaveFavoritos', 'Reemplaza la lista completa de accesos directos del usuario en sesion. Params: { favoritos: ["/ruta1", "/ruta2", ...] } Solo se aceptan cadenas que empiecen por ''/''; el resto se descarta.', True),
    M('GetMenuOculto', 'Modulos que el usuario oculto de su menu (089). Preferencia visual: no quita permisos. CON_SaveMenuOculto Params: { modulos: ["pos", ...] }', False),
    M('SaveMenuOculto', '', True),
    M('IssueAgentToken', 'Emite un token acotado. El token se devuelve UNA sola vez; en la base queda solo su SHA-256. Params: { login?, alcance, dias?, descripcion? } login ausente o igual al de la sesion -> canje interactivo (max 60 min), no requiere ADMIN: el usuario delega en si mismo. login distinto -> requiere ADMIN y que el destino sea usuario de servicio. alcance: ''lectura'' | ''borrador''. ''escritura'' no se emite.', True),
    M('RevokeAgentToken', 'Revoca un token por su hash. Solo ADMIN, o el dueno del token. Params: { token_sha256 }', True),
    M('GetAgentTokens', 'Lista los tokens de la empresa (sin el token, solo metadatos). Solo ADMIN.', False),
    M('GetMisEmpresas', 'Retorna array de empresas donde el usuario actual tiene acceso', False),
    M('GetConsolidado', 'Consolidación: balance agregado de múltiples empresas Params: { anio, mes, empresas: [nit1, nit2, ...] } Returns: [{cuenta_codigo, cuenta_nombre, tipo_cuenta, nivel, naturaleza, clase, debitos_total, creditos_total, saldo_total, detalle: [{nit_empresa, razon_social, debitos, creditos, saldo}]}]', False),
    M('GetAuditLog', 'Lista entradas del log de auditoría Params: { fecha_desde?, fecha_hasta?, usuario?, tabla?, limit? }', False),
    M('GetNotificaciones', 'Retorna alertas activas: nóminas borrador, provisiones pendientes, períodos sin cerrar, comprobantes borrador recientes', False)
  ];

  // Empresa y configuracion (28 ops)
  GModules[1].Tool := 'conta_empresa';
  GModules[1].Title := 'Empresa y configuracion';
  GModules[1].Desc := 'Datos de la empresa, creacion y baja de empresas (tenants), usuarios, permisos y tope de usuarios, configuracion de cuentas contables por defecto, email/notificaciones, exportacion de datos y saldo de IA';
  GModules[1].Methods := [
    M('GetEmpresa', 'Retorna configuración de la empresa del tenant en sesión', False),
    M('SaveEmpresa', 'Actualiza la empresa del tenant en sesión. NO crea empresas: el nit_empresa del payload se IGNORA (un admin solo modifica la suya). Para crear una empresa nueva use CrearEmpresa. Params: { razon_social, pais_codigo, moneda_codigo, grupo_niif, decimales, anio_fiscal_mes } — los ausentes no se tocan', True),
    M('CrearEmpresa', 'Crea una empresa (tenant) NUEVA y su usuario administrador inicial. Falla si el nit_empresa ya existe: para modificar use SaveEmpresa. Requiere perfil ADMIN y que el NIT en sesión esté habilitado para crear empresas (variable de entorno CON_TENANT_ADMIN_NITS en el servidor). Si no se indica admin_login, se replica el usuario que hace la llamada (mismo login y contraseña), de modo que quede acceso inmediato. Params: { nit_empresa, razon_social, pais_codigo, moneda_codigo?, grupo_niif?, decimales?, anio_fiscal_mes?, admin_login?, admin_nombre?, admin_email?, admin_password? } admin_password es SHA-256 hex', True),
    M('GetSaldoIA', 'Saldo del tenant en MKAIServer: saldo, plan, tope y gasto del mes. Params: {} — devuelve {error} si el tenant no tiene cuenta de IA.', False),
    M('RecargarIA', 'Inicia una recarga. SOLO ADMIN: es dinero de la empresa. Params: { monto_usd: number } → { url } del checkout de la pasarela.', True),
    M('GetRecargasIA', 'Historial de recargas del tenant. Params: { limite?: int = 50 }', False),
    M('SincronizarRecargasIA', 'Consulta en la pasarela las recargas pendientes y contabiliza las aprobadas. Params: {} — pensado para llamarse al abrir la pantalla.', True),
    M('SolicitarExportacion', 'Los datos son del cliente: esto le permite llevarselos. El ZIP se prepara en segundo plano; se pregunta por el con GetExportaciones y se descarga por GET /export/download?id=N. SOLO ADMIN. Params: {}', True),
    M('GetExportaciones', 'Estado de las exportaciones del tenant. Params: { limite?: int = 20 }', False),
    M('GetEmpresasAdmin', 'Todas las empresas de la instalacion, para el tenant administrador. CON_GetMisEmpresas no sirve: devuelve donde tiene cuenta el USUARIO, y quien administra la plataforma no la tiene dentro de sus clientes. Params: {}', False),
    M('EliminarEmpresa', 'Borra una empresa y TODOS sus datos. Irreversible. Params: { nit_empresa, confirmacion } — confirmacion debe ser el NIT. Exige estar en CON_TENANT_ADMIN_NITS, que la empresa NO sea la propia y que tenga una exportacion descargable: borrar no puede destruir el unico ejemplar que existe de la contabilidad de alguien.', True),
    M('ProvisionarIA', 'Crea (o recupera) la cuenta de IA del tenant en MKAIServer. Normalmente no hace falta llamarla: CON_CrearEmpresa ya la crea. Existe para reparar un tenant que se quedo sin cuenta porque MKAIServer no respondio. Params: { nit_empresa?: string } — sin nit, el tenant en sesion; con nit ajeno, exige que la empresa este en CON_TENANT_ADMIN_NITS. SOLO ADMIN.', True),
    M('GetUsuarios', 'Lista usuarios de la empresa (sin password). Solo ADMIN.', False),
    M('SaveUsuario', 'Crea o actualiza usuario. Solo ADMIN. Params: { login, nombre, email, perfil, activo, password? } password es SHA-256 hex; opcional en edición (si vacío no se cambia)', True),
    M('GetLimiteUsuarios', 'Tope de usuarios del plan (086): { max_usuarios (null = sin limite), usados }', False),
    M('ChangePassword', 'Cambia la contraseña del usuario en sesión Params: { password_actual, password_nueva } — ambos SHA-256 hex', True),
    M('GetPermisos', 'Retorna permisos por módulo de un usuario Params: { login: string } — solo ADMIN puede consultar otros; el propio usuario se retorna siempre', False),
    M('SavePermisos', 'Guarda permisos de un usuario. Solo ADMIN. Params: { login: string, permisos: { modulo: bool, ... } }', True),
    M('GetConfigEmail', 'Obtiene la configuración SMTP de la empresa', False),
    M('SaveConfigEmail', 'Guarda la configuración SMTP. Params: { smtp_host, smtp_port, smtp_usuario, smtp_password, smtp_ssl, remitente_email, remitente_nombre, activo }', True),
    M('TestEmail', 'Envía un email de prueba al usuario autenticado. Params: {}', True),
    M('EnviarResumenPeriodo', 'Envía resumen del período a los suscriptores. Params: { anio, mes }', True),
    M('GetSuscriptores', 'Lista suscriptores de notificaciones', False),
    M('SaveSuscriptor', 'Agrega/actualiza suscriptor. Params: { email, nombre, activo }', True),
    M('DeleteSuscriptor', 'Elimina suscriptor. Params: { id }', True),
    M('GetConfigCuentas', 'Retorna el mapeo concepto → cuenta para la empresa', False),
    M('SaveConfigCuenta', 'Guarda una entrada de configuración de cuentas Params: { concepto: string, cuenta_codigo: string, descripcion: string }', True),
    M('DeleteConfigCuenta', 'Elimina un mapeo concepto→cuenta. Params: { concepto: string }', True)
  ];

  // Plan de cuentas (PUC) (6 ops)
  GModules[2].Tool := 'conta_puc';
  GModules[2].Title := 'Plan de cuentas (PUC)';
  GModules[2].Desc := 'PUC maestro Colombia y plan de cuentas de la empresa: consultar, crear, modificar, eliminar cuentas';
  GModules[2].Methods := [
    M('GetPucMaestro', 'Retorna el plan de cuentas maestro de un país (niveles 1-4) Params: { pais: string } — ej. ''CO''', False),
    M('ImportarPucMaestro', 'Importa cuentas del PUC maestro a la empresa en sesión Params: { pais: string, nivel_max: integer (1-4) } Retorna: { cuentas_importadas: integer }', True),
    M('GetPlanCuentas', 'Retorna el plan de cuentas con estructura jerárquica Params: { solo_activas: bool, acepta_movto: bool, nivel_max: int, buscar: string }', False),
    M('GetCuenta', 'Retorna una cuenta por código Params: { codigo: string }', False),
    M('SaveCuenta', 'Crea o actualiza una cuenta nivel, codigo_padre y tipo_cuenta se derivan del codigo si no se envian. es_nuevo = true rechaza el guardado si el codigo ya existe. Params: { codigo, nombre, tipo_cuenta, codigo_padre, es_nuevo, acepta_movto, requiere_tercero, requiere_centro_costo, requiere_documento, activa }', True),
    M('DeleteCuenta', 'Desactiva una cuenta (soft delete — solo si no tiene movimientos) Params: { codigo: string }', True)
  ];

  // Terceros (6 ops)
  GModules[3].Tool := 'conta_terceros';
  GModules[3].Title := 'Terceros';
  GModules[3].Desc := 'Clientes, proveedores, empleados y demas terceros: consultar y mantener, con sus sucursales';
  GModules[3].Methods := [
    M('GetTerceros', 'Lista terceros con filtro opcional Params: { buscar: string, es_cliente: bool, es_proveedor: bool, page: int, page_size: int }', False),
    M('GetTercero', 'Retorna un tercero por tipo_id + numero_id Params: { tipo_id: string, numero_id: string }', False),
    M('SaveTercero', 'Crea o actualiza tercero Params: { tipo_id, numero_id, digito_verif, razon_social, es_cliente, es_proveedor, email, telefono, direccion, ciudad, pais_codigo }', True),
    M('GetTerceroSucursales', 'Un tercero sin sucursales se comporta como siempre: son opcionales. Existen porque Siigo las modela y hasta la 070 se perdian al migrar. Lista las sucursales de un tercero. Params: { tipo_id, numero_id, solo_activas?: bool = true }', False),
    M('SaveTerceroSucursal', 'Crea o actualiza una sucursal. Params: { tipo_id, numero_id, codigo, nombre, direccion?, ciudad?, departamento?, telefono?, email?, activo? }', True),
    M('DeleteTerceroSucursal', 'Desactiva una sucursal (soft-delete: puede estar referenciada por documentos) Params: { tipo_id, numero_id, codigo }', True)
  ];

  // Comprobantes contables (13 ops)
  GModules[4].Tool := 'conta_comprobantes';
  GModules[4].Title := 'Comprobantes contables';
  GModules[4].Desc := 'Comprobantes de contabilidad: crear, contabilizar, anular, revisar; tipos de comprobante y plantillas recurrentes';
  GModules[4].Methods := [
    M('GetPlantillas', 'GetPlantillas: {} → [{id,nombre,comp_tipo,descripcion,activa,movimientos:[...]}] SavePlantilla: {id?,nombre,comp_tipo,descripcion,activa,movimientos:[...]} DeletePlantilla: {id} AplicarPlantilla: {id,fecha,descripcion?} → {status,tipo_codigo,numero}', False),
    M('SavePlantilla', '', True),
    M('DeletePlantilla', '', True),
    M('AplicarPlantilla', '', True),
    M('GetTiposComprobante', 'Retorna tipos de comprobante activos', False),
    M('SaveTipoComprobante', 'Crea o actualiza tipo de comprobante Params: { codigo, nombre, prefijo, numeracion_auto, permite_edicion, activo }', True),
    M('GetComprobantes', 'Lista comprobantes con filtros y paginación Params: { tipo_codigo, fecha_desde, fecha_hasta, estado, buscar, centro_operacion_codigo, page, page_size }', False),
    M('GetComprobante', 'Retorna un comprobante con sus movimientos Params: { tipo_codigo: string, numero: int }', False),
    M('SaveComprobante', 'Guarda comprobante (cabecera + movimientos) El comprobante queda en estado BORRADOR Valida: débitos = créditos Params: { tipo_codigo, fecha, descripcion, ref_tipo, ref_numero, centro_operacion_codigo?, movimientos: [ { linea, cuenta_codigo, tercero_tipo_id, tercero_numero_id, centro_costo_codigo, debito, credito, descripcion, base_impuesto, documento_ref } ] } documento_ref es obligatorio en cuentas con requiere_documento = TRUE centro_operacion_codigo es obligatorio si con_empresas.co_obligatorio', True),
    M('ContabilizarComprobante', 'Contabiliza un comprobante (BORRADOR → CONTABILIZADO) Actualiza tabla con_saldos. Valida período abierto. Params: { tipo_codigo: string, numero: int }', True),
    M('AnularComprobante', 'Anula un comprobante (CONTABILIZADO → ANULADO) Revierte los saldos. Params: { tipo_codigo: string, numero: int }', True),
    M('RevisarComprobante', 'Marca un comprobante BORRADOR como REVISADO (requiere rol admin o aprobador) Params: { tipo_codigo, numero, comentario? }', True),
    M('RechazarComprobante', 'Rechaza un comprobante REVISADO → vuelve a BORRADOR Params: { tipo_codigo, numero, motivo }', True)
  ];

  // Periodos y cierre anual (6 ops)
  GModules[5].Tool := 'conta_periodos';
  GModules[5].Title := 'Periodos y cierre anual';
  GModules[5].Desc := 'Apertura y cierre de periodos contables y proceso de cierre anual';
  GModules[5].Methods := [
    M('GetPeriodos', 'Lista períodos del tenant. Params: { anio: int }', False),
    M('AbrirPeriodo', 'Abre un período (crea si no existe). Params: { anio: int, mes: int }', True),
    M('CerrarPeriodo', 'Cierra un período. Params: { anio: int, mes: int } Valida que no existan comprobantes en BORRADOR', True),
    M('GetCierresAnuales', 'Historial de cierres anuales ejecutados', False),
    M('ValidarCierreAnio', 'Valida si se puede cerrar el año sin ejecutar cambios Params: { anio: int } Returns: { puede_cerrar, errores[], advertencias[], utilidad_estimada, total_ingresos, total_gastos_costos, cuenta_utilidad }', False),
    M('CerrarAnio', 'Ejecuta el cierre anual completo: 1. Asiento de cierre (R → UTILIDAD_EJERCICIO) 2. Asiento de apertura del siguiente año (B accounts) Params: { anio: int } Returns: { ok, comp_cierre, comp_apertura, utilidad }', True)
  ];

  // Retenciones (9 ops)
  GModules[6].Tool := 'conta_retenciones';
  GModules[6].Title := 'Retenciones';
  GModules[6].Desc := 'Retenciones (fuente, IVA, ICA): configuracion, asignacion a terceros, sugerencias y reporte; tarifas de IVA de la empresa';
  GModules[6].Methods := [
    M('GetRetenciones', 'Catálogo de retenciones. Params: { solo_activas: bool }', False),
    M('SaveRetencion', 'CRUD retención. Solo ADMIN. Params: { codigo, nombre, tipo, base_calculo, tarifa, cuenta_debito, cuenta_credito, activo }', True),
    M('DeleteRetencion', 'Desactiva una retención (soft-delete). Params: { codigo: string }', True),
    M('GetTarifasIva', 'Catalogo por empresa. Params: { solo_activas: bool } -> [{codigo, nombre, porcentaje, tipo, norma, descripcion, activo, en_uso}]', False),
    M('SaveTarifaIva', 'Crea o actualiza una tarifa. Solo ADMIN. El porcentaje y el tipo de una tarifa ya usada no se cambian: se crea otra y se desactiva la vieja. Params: { codigo, nombre, porcentaje, tipo, norma?, descripcion?, activo }', True),
    M('GetRetencionesTercero', 'Retenciones configuradas para un tercero (con tarifa efectiva y flag asignada) Params: { tipo_id: string, numero_id: string }', False),
    M('GetRetencionSugerida', 'Retenciones sugeridas calculadas para una línea de comprobante Params: { tercero_tipo_id, tercero_numero_id, base_gravable } Returns: [{cuenta_debito, cuenta_credito, descripcion, tarifa, monto, tipo}]', False),
    M('SaveRetencionesTercero', 'Guarda (reemplaza) las retenciones asignadas a un tercero Params: { tipo_id, numero_id, retenciones: [{retencion_codigo, tarifa_override?}] }', True),
    M('RPT_Retenciones', 'Totales por cuenta y tercero para cuentas 2365/2367/2368/1355 Params: { anio, mes_desde, mes_hasta }', False)
  ];

  // Centros de costo (8 ops)
  GModules[7].Tool := 'conta_centros_costo';
  GModules[7].Title := 'Centros de costo';
  GModules[7].Desc := 'Centros de costo y centros de operacion: mantenimiento y reporte por centro de costo';
  GModules[7].Methods := [
    M('GetCentrosCosto', 'Params: {} — retorna todos los activos', False),
    M('SaveCentroCosto', 'Params: { codigo, nombre, codigo_padre, activo }', True),
    M('DeleteCentroCosto', 'Desactiva un centro de costo (soft-delete). Params: { codigo: string }', True),
    M('GetCentrosOperacion', '── Centros de Operacion (dimension de encabezado de comprobante) ───── Params: { solo_activos?: bool }', False),
    M('SaveCentroOperacion', 'Params: { codigo, nombre, activo }', True),
    M('DeleteCentroOperacion', 'Desactiva un centro de operacion (soft-delete). Params: { codigo: string }', True),
    M('RPT_CentroCosto', 'Totales débito/crédito/saldo agrupados por CC y cuenta Params: { anio, mes_desde, mes_hasta, centro_costo_codigo? }', False),
    M('RPT_PyGCentroCosto', 'Estado de Resultados (P&G) desglosado por Centro de Costo Params: { anio, mes_desde, mes_hasta } Returns: filas planas { cc_codigo, cc_nombre, cuenta_codigo, cuenta_nombre, nivel, naturaleza, debitos, creditos, saldo } Solo cuentas clase R (resultado). El FE las pivotea por CC.', False)
  ];

  // Reportes contables (22 ops)
  GModules[8].Tool := 'conta_reportes';
  GModules[8].Title := 'Reportes contables';
  GModules[8].Desc := 'Balance, PyG (tambien por centro de operacion), auxiliares, libros oficiales, libro de IVA, libro por tercero, analisis horizontal e inventario contra contabilidad';
  GModules[8].Methods := [
    M('RPT_BalancePrueba', 'Balance de Prueba Params: { anio: int, mes_desde: int, mes_hasta: int }', False),
    M('RPT_LibroDiario', 'Libro Diario Params: { anio: int, mes: int, tipo_codigo: string, fecha_desde, fecha_hasta }', False),
    M('RPT_LibroMayor', 'Libro Mayor por cuenta Params: { cuenta_codigo: string, anio: int, mes_desde: int, mes_hasta: int }', False),
    M('RPT_BalanceGeneral', 'Balance General (Estado de Situación Financiera) Acumula cuentas clase=''B'' desde mes 1 hasta el mes indicado Params: { anio: int, mes: int }', False),
    M('RPT_EstadoResultados', 'Estado de Resultados Cuentas clase=''R'' para el rango de meses indicado Params: { anio: int, mes_desde: int, mes_hasta: int }', False),
    M('RPT_Cartera', 'Cartera — Aging de cuentas por cobrar/pagar Params: { tipo: ''COBRAR''|''PAGAR'', fecha_corte: ''YYYY-MM-DD'', tercero_numero_id? } ← filtra un solo tercero en el servidor Returns: array of { tercero_tipo_id, tercero_numero_id, nombre, saldo_total, corriente, dias_31_60, dias_61_90, dias_91_120, mayor_120 }', False),
    M('RPT_CarteraPorCuenta', 'Cartera con desglose por cuenta contable Params: { tipo: ''COBRAR''|''PAGAR'', fecha_corte: string, cuenta_desde?: string, cuenta_hasta?: string } Returns: array of { tercero_*, cuenta_codigo, cuenta_nombre, nombre, aging cols }', False),
    M('RPT_CertificadoRetencion', 'Certificado de Retención en la Fuente (Formato 220) Params: { anio, tercero_tipo_id, tercero_numero_id } Returns: array de { cuenta_codigo, cuenta_nombre, tipo_retencion, valor_retenido }', False),
    M('GetTRM', 'TRM — Tasas de cambio GetTRM: { moneda_codigo?, fecha_desde?, fecha_hasta? } → [{moneda_codigo,fecha,tasa,fuente}] SaveTRM: { moneda_codigo, fecha, tasa, fuente? } → {status} DeleteTRM: { moneda_codigo, fecha } → {status} GetTRMVigente: { moneda_codigo, fecha } → {tasa} o error AjusteDiferenciaCambio: { anio, mes, comp_tipo } → {status, comp_numero, total_ajuste}', False),
    M('SaveTRM', '', True),
    M('DeleteTRM', '', True),
    M('GetTRMVigente', '', False),
    M('AjusteDiferenciaCambio', '', True),
    M('ImportarTRMBanRep', 'Importa TRM USD desde API pública BanRep Params: { fecha_desde, fecha_hasta } Returns: { status, importadas, errores }', True),
    M('RPT_Dashboard', 'Dashboard KPIs Params: { anio: int, mes: int } Returns: { meses:[{mes,mes_nombre,ingresos,gastos,utilidad}], cartera_cobrar, cartera_pagar, utilidad_anio, comprobantes_mes, borradores_mes }', False),
    M('ImportarComprobantes', 'Importación masiva de comprobantes desde Excel Params: { comprobantes: [{tipo_codigo, fecha, descripcion, ref_tipo, ref_numero, movimientos:[{cuenta_codigo, tercero_tipo_id, tercero_numero_id, centro_costo_codigo, debito, credito, descripcion}]}] } Returns: { guardados: int, errores: [{indice, mensaje}] }', True),
    M('RPT_LibroIVA', 'Movimientos en cuentas de IVA (prefijo ''24'' por defecto) Params: { anio, mes_desde, mes_hasta, prefijo_cuenta? }', False),
    M('RPT_PyGCentroOperacion', 'PyG por centro de operacion (dimension del encabezado del comprobante). Params: { anio, mes_desde, mes_hasta } Returns: filas planas { co_codigo, co_nombre, cuenta_codigo, cuenta_nombre, nivel, naturaleza, debitos, creditos, saldo } Solo cuentas clase R (resultado). El FE las pivotea por CO.', False),
    M('RPT_LibroTercero', 'Movimientos con saldo acumulado filtrados por tercero y rango de cuentas Params: { anio, mes_desde, mes_hasta, cuenta_desde?, cuenta_hasta?, tercero_id? }', False),
    M('RPT_BalanceComprobacion', 'Balance de Comprobación agrupado por niveles configurables Params: { anio, mes_desde, mes_hasta, niveles: string (e.g. "cuenta,tercero,centro_costo") } niveles puede ser cualquier combinación/orden de: cuenta | tercero | centro_costo | centro_operacion', False),
    M('RPT_AnalisisHorizontal', 'Compara movimientos (débito/crédito) de dos períodos y calcula variaciones Params: { anio_a, mes_desde_a, mes_hasta_a, anio_b, mes_desde_b, mes_hasta_b }', False),
    M('RPT_InventarioContabilidad', 'Inventario contra contabilidad (098): por cuenta de inventario, el valor del kardex frente al saldo contable, con el detalle por articulo. Params: {} -> { cuentas: [...], articulos: [...] }', False)
  ];

  // Activos fijos (8 ops)
  GModules[9].Tool := 'conta_activos_fijos';
  GModules[9].Title := 'Activos fijos';
  GModules[9].Desc := 'Activos fijos: registro, depreciacion, bajas y revaluaciones';
  GModules[9].Methods := [
    M('GetActivosFijos', 'Lista todos los activos con estado de depreciación', False),
    M('SaveActivoFijo', 'UPSERT de un activo fijo Params: { codigo, descripcion, categoria, fecha_adquisicion, valor_adquisicion, valor_residual, vida_util_meses, metodo, cuenta_activo, cuenta_dep_acum, cuenta_gasto_dep, activo }', True),
    M('DeleteActivoFijo', 'Desactiva un activo Params: { codigo }', True),
    M('PreviewDepreciacion', 'Preview de depreciación del período (sin guardar) Params: { anio: int, mes: int } Returns: array of { codigo, descripcion, valor_dep, ya_depreciado }', False),
    M('EjecutarDepreciacion', 'Ejecuta la depreciación: crea comprobante DEP y registra en con_depreciaciones Params: { anio: int, mes: int } Returns: { ok, comp_tipo, comp_numero, activos_depreciados, total_depreciacion }', True),
    M('BajaActivoFijo', 'Baja (retiro/venta/siniestro) de un activo — crea comprobante BAJ Params: { codigo, fecha_baja, tipo_baja, valor_venta, cuenta_destino?, cuenta_resultado, anio, mes }', True),
    M('RevaluarActivoFijo', 'Revalua un activo — actualiza valor_adquisicion, crea comprobante REVAL Params: { codigo, nuevo_valor, cuenta_ajuste, anio, mes }', True),
    M('GetHistorialDepreciaciones', 'Historial completo de depreciaciones de todos los activos Returns: array of { activo_codigo, descripcion, categoria, anio, mes, valor, comp_tipo, comp_numero }', False)
  ];

  // Presupuestos (7 ops)
  GModules[10].Tool := 'conta_presupuestos';
  GModules[10].Title := 'Presupuestos';
  GModules[10].Desc := 'Presupuestos por cuenta/centro de costo y ejecucion presupuestal';
  GModules[10].Methods := [
    M('GetPresupuestos', 'Lista presupuestos (cabeceras)', False),
    M('SavePresupuesto', 'UPSERT cabecera de presupuesto Params: { anio, descripcion, estado }', True),
    M('DeletePresupuesto', 'Elimina presupuesto y su detalle (solo en estado BORRADOR). Params: { anio: int }', True),
    M('GetPresupuestoDetalle', 'Detalle de un presupuesto (cuenta × mes) Params: { anio } Returns: array of { cuenta_codigo, nombre_cuenta, mes_1..mes_12, total }', False),
    M('SavePresupuestoDetalle', 'Guarda líneas de detalle (reemplaza todo el año) Params: { anio, lineas: [{cuenta_codigo, mes_1..mes_12}] }', True),
    M('ImportarPresupuesto', 'Importa filas de presupuesto desde Excel (UPSERT fila por fila) Params: { filas: [{cuenta_codigo, anio, mes, valor, descripcion?}] } Returns: { guardados: int, errores: [{indice, mensaje}] }', True),
    M('RPT_PresupuestoVsReal', 'Reporte comparativo presupuesto vs real Params: { anio, mes_hasta } Returns: array of { cuenta_codigo, nombre, clase, naturaleza, pres_1..pres_12, real_1..real_12, pres_total, real_total, variacion, pct }', False)
  ];

  // Conciliacion bancaria (14 ops)
  GModules[11].Tool := 'conta_conciliacion';
  GModules[11].Title := 'Conciliacion bancaria';
  GModules[11].Desc := 'Conciliacion bancaria e importacion de extractos CSV';
  GModules[11].Methods := [
    M('GetConciliaciones', 'Lista conciliaciones de la empresa', False),
    M('IniciarConciliacion', 'Abre/crea una nueva conciliación para cuenta+período Params: { cuenta_codigo, anio, mes, saldo_extracto } Returns: { id, cuenta_codigo, anio, mes, ... }', True),
    M('GetMovtosConciliacion', 'Movimientos contables de la cuenta en el período (con flag conciliado) Params: { conciliacion_id } Returns: array of { comp_tipo, comp_numero, linea, fecha, descripcion, debito, credito, conciliado }', False),
    M('MarcarMovtoConciliado', 'Marcar/desmarcar movimiento contable como conciliado Params: { conciliacion_id, comp_tipo, comp_numero, linea, conciliado }', True),
    M('GetExtractoItems', 'CRUD items del extracto Lista items del extracto para una conciliacion Params: { conciliacion_id }', False),
    M('SaveExtractoItems', 'Params: { conciliacion_id, items: [{fecha, descripcion, debito, credito}] }', True),
    M('MarcarExtractoConciliado', 'Marcar/desmarcar item extracto como conciliado Params: { conciliacion_id, item_id, conciliado }', True),
    M('CerrarConciliacion', 'Cierra la conciliación si diferencia = 0 Params: { conciliacion_id }', True),
    M('ReabrirConciliacion', 'Reabre una conciliación previamente cerrada Params: { conciliacion_id }', True),
    M('GetExtractos', 'Lista de extractos importados para la empresa', False),
    M('SaveExtracto', 'Guarda cabecera + líneas de extracto Params: { cuenta_codigo, nombre_archivo, lineas: [{fecha, descripcion, referencia, debito, credito, saldo}] }', True),
    M('GetExtractoLineas', 'Líneas de un extracto Params: { extracto_id }', False),
    M('DeleteExtracto', 'Elimina un extracto (cabecera + líneas) si ninguna línea está conciliada Params: { extracto_id }', True),
    M('DeleteProvisiones', 'Elimina provisiones NO contabilizadas de un período Params: { anio, mes }', True)
  ];

  // Flujo de efectivo (4 ops)
  GModules[12].Tool := 'conta_flujo_efectivo';
  GModules[12].Title := 'Flujo de efectivo';
  GModules[12].Desc := 'Estado de flujo de efectivo (metodo indirecto)';
  GModules[12].Methods := [
    M('GetConfigEFE', 'Configuración del mapeo cuenta → sección EFE', False),
    M('SaveConfigEFE', 'Guarda/actualiza un mapeo de cuenta → sección EFE Params: { cuenta_codigo, seccion, orden, nombre_linea, signo }', True),
    M('DeleteConfigEFE', 'Elimina un mapeo de cuenta del EFE Params: { cuenta_codigo }', True),
    M('RPT_FlujoEfectivo', 'Genera el Estado de Flujos de Efectivo Params: { anio, mes }', False)
  ];

  // Informacion exogena DIAN (5 ops)
  GModules[13].Tool := 'conta_exogena';
  GModules[13].Title := 'Informacion exogena DIAN';
  GModules[13].Desc := 'Medios magneticos / informacion exogena DIAN';
  GModules[13].Methods := [
    M('GetExogenaConceptos', 'Lista de conceptos configurados para un año Params: { anio }', False),
    M('SaveExogenaConcepto', 'Crea o actualiza un concepto de exógena Params: { anio, concepto, descripcion, cuenta_desde, cuenta_hasta, naturaleza_mov, umbral, activo }', True),
    M('DeleteExogenaConcepto', 'Desactiva un concepto de exógena (soft-delete). Params: { anio: int, concepto: string }', True),
    M('GenerarExogena', 'Genera (o regenera) los resultados de todos los conceptos del año Params: { anio }', True),
    M('GetExogenaResultado', 'Devuelve el resultado generado Params: { anio, concepto? }', False)
  ];

  // Facturacion electronica (28 ops)
  GModules[14].Tool := 'conta_facturacion_electronica';
  GModules[14].Title := 'Facturacion electronica';
  GModules[14].Desc := 'Integracion FEV/DIAN: emision, consulta de documentos, acuses, RADIAN, documento soporte, folios y configuracion FE';
  GModules[14].Methods := [
    M('GetFacturasPendientesFEV', 'Lista facturas ACEPTADAS en fevsdb que aún no han sido contabilizadas Params: { fecha_desde, fecha_hasta, page, page_size }', False),
    M('ContabilizarFacturaFEV', 'Genera asiento contable automático desde una factura FEVs (CUFE) Usa con_config_cuentas para determinar las cuentas Params: { cufe: string }', True),
    M('EmitirFacturaElectronica', 'Emite una factura electrónica vía FEVs → DIAN. Params: { documento_id: int } Returns: { cufe, estado, status_message, track_id? }', True),
    M('GetFEDocumentos', 'Historial de documentos FE emitidos desde contabilidad Params: { estado?, fecha_desde?, fecha_hasta?, page?, page_size? }', False),
    M('ConsultarEstadoFE', 'Consulta estado DIAN de un documento FE (via FEVs) Params: { cufe: string } Returns: { cufe, estado, status_message }', True),
    M('ReenviarCorreoFE', 'Reenvia al cliente el correo de un documento ya aceptado por la DIAN. Params: { documento_id }', True),
    M('GetAcusesFE', 'Acuses / eventos RADIAN de una factura (030 acuse, 031 reclamo, 032 recibo del bien, 033 aceptacion expresa, 034 tacita), consultados en vivo a la DIAN por FEVS (GET /radian/api/v1/eventos/{cufe}, Bearer). Params: { cufe } -> { cufe, documento, consultado, total, eventos[], resumen{}, dian_status, dian_message }', False),
    M('GetArchivoFE', 'Representacion grafica (PDF) o XML (AttachedDocument) de un documento FE. Params: { cufe, tipo: ''pdf''|''xml'' } -> { nombre, mime, base64, origen }', False),
    M('GetFolios', 'Saldo, lotes, compras, consumos y paquetes de la empresa en sesion.', False),
    M('ComprarFolios', 'Inicia la compra de un paquete por Wompi (cuenta del vendedor). ADMIN. Params: { paquete_id } -> { url, referencia }', True),
    M('SincronizarFolios', 'Respaldo del webhook: consulta en Wompi las compras pendientes y contabiliza las aprobadas. Params: { referencia? }', True),
    M('GetFoliosPlataforma', 'Plataforma (CON_TENANT_ADMIN_NITS): saldo y compras de todas las empresas', False),
    M('AbonarFolios', 'Plataforma: regalar o ajustar folios. Params: { nit_empresa, folios, vigencia_meses, motivo, origen? (CORTESIA|AJUSTE) }', True),
    M('SaveFoliosConfig', 'Plataforma: { folios_vendedor_nit?, folios_cobro_activo?, folios_sobregiro?, folios_activacion?, erp_url_publica? }', True),
    M('CrearFacturasFolios', 'Empresa vendedora: crea en BORRADOR la factura de cada compra aprobada', True),
    M('ValidarDocumentoSoporte', 'Revisa si una factura de proveedor marcada como documento soporte esta lista para emitirse ante la DIAN. No envia nada. Params: { id } -> { listo, problemas[], avisos[], prefijo, siguiente_numero }', False),
    M('EmitirDocumentoSoporte', 'Emite ante la DIAN (via FEVS) un documento soporte (05) o su nota de ajuste (95). Params: { id } -> mismo formato que CON_EmitirFacturaElectronica', True),
    M('GetFEConfig', 'Retorna configuración de software emisor FE', False),
    M('SaveFEConfig', 'Guarda configuración FE (UPSERT) Params: { software_id, software_pin, cert_pfx_ruta, cert_password, cert_vence?, ambiente, set_pruebas_id? }', True),
    M('GetFEResoluciones', 'Lista resoluciones de facturación DIAN de la empresa Params: { activa? }', False),
    M('SaveFEResolucion', 'Crea o actualiza una resolución DIAN (UPSERT por id) Params: { id?, prefijo, numero_desde, numero_hasta, numero_actual?, fecha_desde, fecha_hasta, clave_tecnica, tipo_doc, ambiente, activa? }', True),
    M('DeleteFEResolucion', 'Desactiva (soft-delete) una resolución DIAN Params: { id: int }', True),
    M('GetEventosRadian', 'Retorna eventos RADIAN de una factura electronica (circulacion, factoring, etc.) Params: { cufe: string } Returns: { status_code, eventos: [{eventCode, issueDate, senderParty, isValid, cuds}] }', False),
    M('GetNotasReferencia', 'Retorna si existen notas credito/debito asociadas en DIAN para un CUFE Params: { cufe: string } Returns: { is_valid, status_code, status_description }', False),
    M('GetAdquirienteFEV', 'Retorna datos del adquiriente registrado en DIAN (para autocompletar cliente) Params: { nit: string, tipo_id?: string } tipo_id default "31" (NIT) Returns: { status_code, receiver_name?, receiver_email? }', False),
    M('ProcesarPendientesFE', 'Procesa en lote todos los docs FE en estado PENDIENTE/EMITIDA: consulta FEVs y actualiza estado en BD Returns: { actualizados: int, aceptados: int, errores: int }', True),
    M('GetDocumentosParaEmitirFE', 'Lista facturas en estado FACTURADO que aun no tienen FE emitida Params: { limit?: int } default 50 Returns: [{id, numero, fecha, total, tercero_numero_id, razon_social}]', False),
    M('GetResumenFEVentas', 'Alertas de facturacion electronica de ventas (de toda la empresa) Returns: { pendientes, rechazadas, sin_correo }', False)
  ];

  // Importacion masiva (8 ops)
  GModules[15].Tool := 'conta_importacion';
  GModules[15].Title := 'Importacion masiva';
  GModules[15].Desc := 'Importacion masiva CSV: terceros, articulos, plan de cuentas, centros de costo, activos fijos, novedades de nomina, retenciones y saldos de inventario';
  GModules[15].Methods := [
    M('ImportarTerceros', 'Params: { terceros: [{tipo_id, numero_id, razon_social, nombre_comercial?, digito_verif?, es_cliente, es_proveedor, email?, telefono?, direccion?, ciudad?, departamento?, pais_codigo?, regimen?, cuenta_cobrar?, cuenta_pagar?}] } Returns: { guardados: int, errores: [{indice, mensaje}] }', True),
    M('ImportarArticulos', 'Params: { articulos: [{codigo, nombre, tipo?, unidad_medida?, metodo_costeo?, maneja_inventario?, precio_venta_default?, impuesto_pct?, cuenta_inventario?, cuenta_costo_ventas?, cuenta_ventas?}] } Returns: { guardados: int, errores: [{indice, mensaje}] }', True),
    M('ImportarCuentas', 'Params: { cuentas: [{codigo, nombre, tipo_cuenta, acepta_movto?, requiere_tercero?, requiere_centro_costo?, requiere_documento?, codigo_padre?, activa?}] }', True),
    M('ImportarCentrosCosto', 'Params: { centros: [{codigo, nombre, codigo_padre?, activo?}] }', True),
    M('ImportarActivosFijos', 'Params: { activos: [{codigo, descripcion, categoria?, fecha_adquisicion, valor_adquisicion, valor_residual?, vida_util_meses, metodo?, cuenta_activo, cuenta_dep_acum, cuenta_gasto_dep, activo?}] }', True),
    M('ImportarNovedades', 'Params: { novedades: [{anio, mes, empleado_tipo_id, empleado_numero_id, tipo_novedad, dias, descripcion?}] }', True),
    M('ImportarRetenciones', 'Params: { retenciones: [{codigo, nombre, tipo, base_calculo?, tarifa, cuenta_debito, cuenta_credito, activo?}] }', True),
    M('ImportarSaldosInventario', 'Params: { saldos: [{articulo_codigo, bodega_codigo, cantidad, costo_unitario}] }', True)
  ];

  // Nomina (32 ops)
  GModules[16].Tool := 'conta_nomina';
  GModules[16].Title := 'Nomina';
  GModules[16].Desc := 'Nomina Colombia: liquidacion, novedades, descuentos, provisiones, conceptos, IBC, acumulados, certificado 220, liquidacion definitiva, nomina electronica DIAN y parametros legales (SMMLV)';
  GModules[16].Methods := [
    M('ValidarNominaElectronica', 'Nomina electronica (migracion 083)', False),
    M('EmitirNominaElectronica', '', True),
    M('ConsultarNominaElectronica', '', True),
    M('EmitirAjusteNomina', 'Nomina de ajuste: reemplazar / eliminar (migracion 085)', True),
    M('GetParametrosLegales', 'Salario minimo, auxilio de transporte... por año, con su norma (084)', False),
    M('GetEmpleados', '', False),
    M('SaveEmpleado', 'Params: { tipo_id, numero_id, nombres, apellidos, cargo, fecha_ingreso, salario_basico, tipo_contrato, cuenta_salarios, cuenta_prestaciones, cuenta_aportes_emp, cuenta_pagar_emp, cuenta_pagar_seg, activo }', True),
    M('ImportarEmpleados', 'Importa empleados desde Excel (UPSERT por tipo_id+numero_id) Params: { empleados: [{tipo_id, numero_id, nombres, apellidos, cargo?, fecha_ingreso, tipo_contrato, salario_basico, dias_trabajados_mes?, cuenta_salarios, cuenta_prestaciones, cuenta_aportes_emp, cuenta_pagar_emp, cuenta_pagar_seg}] } Returns: { guardados: int, errores: [{indice, mensaje}] }', True),
    M('GetNovedades', 'Params: { anio, mes, empleado_tipo_id?, empleado_numero_id? }', False),
    M('SaveNovedad', 'Params: { id?, anio, mes, empleado_tipo_id, empleado_numero_id, tipo_novedad, dias, descripcion }', True),
    M('DeleteNovedad', 'Params: { id }', True),
    M('GetDescuentos', 'Params: { empleado_tipo_id, empleado_numero_id, solo_activos? }', False),
    M('SaveDescuento', 'Params: { id?, empleado_tipo_id, empleado_numero_id, tipo_descuento, descripcion, valor_mensual, activo, fecha_inicio, fecha_fin? }', True),
    M('DeleteDescuento', 'Params: { id }', True),
    M('GetNominas', '', False),
    M('GetDashboardNomina', 'Dashboard KPIs de nómina Params: { anio } Returns: { meses:[{mes,mes_nombre,devengado,aportes_emp,costo_total,empleados}], total_anio_devengado, total_anio_aportes, total_anio_costo, top_cargos:[{cargo,costo_total,empleados}], promedio_mensual }', False),
    M('LiquidarNomina', 'Crea una nómina en borrador con los empleados activos y calcula aportes Params: { anio, mes, smmlv (salario mínimo vigente) } Returns: { id, total_devengado, total_deducciones, total_neto, total_aportes_emp }', True),
    M('GetNominaDetalle', 'Detalle de empleados de una nómina Params: { nomina_id }', False),
    M('UpdateNominaEmpleado', 'Actualiza valores de un empleado en la nómina (horas extras, otros, etc.) Params: { nomina_id, empleado_tipo_id, empleado_numero_id, horas_extras, otros_devengados, otras_deducciones }', True),
    M('ContabilizarNomina', 'Contabiliza la nómina: genera comprobante NOM Params: { nomina_id }', True),
    M('LiquidarProvisiones', 'Calcula/recalcula provisiones del mes a partir de la nómina liquidada Params: { anio, mes } Returns: { status, total_empleados, total_provisiones }', True),
    M('GetProvisiones', 'Lista provisiones — Params: { anio, mes? }', False),
    M('ContabilizarProvisiones', 'Contabiliza las provisiones del mes — Params: { anio, mes, comp_tipo }', True),
    M('GetAcumuladoNomina', 'Totales por empleado agrupados por mes — Params: { anio, empleado_tipo_id?, empleado_numero_id? }', False),
    M('GetCertificado220', 'Params: { anio, empleado_tipo_id, empleado_numero_id }', False),
    M('LiquidacionDefinitiva', 'Calcula liquidación al retirar un empleado Params: { empleado_tipo_id, empleado_numero_id, fecha_retiro, causa_retiro }', False),
    M('GetConceptosNomina', 'Params: {}', False),
    M('SaveConceptoNomina', 'Params: { id?, codigo, nombre, tipo, es_constitutivo, porcentaje?, activo }', True),
    M('IniciarConceptosNomina', 'Params: {} — siembra conceptos sistema para la empresa si no existen', True),
    M('GetEmpConceptos', '', False),
    M('SaveEmpConcepto', '', True),
    M('DeleteEmpConcepto', '', True)
  ];

  // Inventario (25 ops)
  GModules[17].Tool := 'conta_inventario';
  GModules[17].Title := 'Inventario';
  GModules[17].Desc := 'Articulos, bodegas, armados, traslados, entradas y salidas manuales, movimientos y saldos de inventario';
  GModules[17].Methods := [
    M('GetCategoriasInv', 'Categorías', False),
    M('SaveCategoriaInv', '', True),
    M('GetArticulos', 'Artículos Params: { buscar?, tipo?, activo?, categoria_id? }', False),
    M('GetArticulo', 'Params: { codigo }', False),
    M('SaveArticulo', '', True),
    M('DeleteArticulo', 'Params: { codigo }', True),
    M('GetBodegas', 'Bodegas Params: { solo_activas? }', False),
    M('SaveBodega', '', True),
    M('SetBodegaPorDefecto', 'Fija la bodega por defecto de la empresa (091). Solo ADMIN. Params: { codigo }. Es la de los productos sin bodega propia y la que propone el formulario al crear un producto.', True),
    M('SaveArmado', 'Toma productos del inventario y arma uno nuevo para la venta, en un solo paso: crea el producto (o usa uno existente), da de baja los componentes a costo promedio, da entrada al producto con la suma y, si las cuentas de inventario difieren, hace el comprobante. Params: { fecha?, cantidad? (1), notas?, producto: { codigo? (vacio = ARM-nnnnn), nombre, precio_venta, tarifa_iva, bodega_codigo?, unidad_medida? }, componentes: [{ articulo_codigo, bodega_codigo?, cantidad }] }', True),
    M('GetArmados', 'Params: { fecha_desde?, fecha_hasta? }', False),
    M('GetArmado', 'Params: { id } -> encabezado + componentes', False),
    M('SaveTraslado', '', True),
    M('GetTraslados', '', False),
    M('GetTraslado', 'Params: { id }', False),
    M('GetSaldosInventario', 'Saldos y Kardex Params: { bodega_codigo?, articulo_codigo?, buscar? }', False),
    M('GetKardex', 'Params: { articulo_codigo, bodega_codigo?, fecha_desde?, fecha_hasta? }', False),
    M('GetAjustesInventario', 'Ajustes de inventario Params: { estado? }', False),
    M('GetAjusteInventario', 'Params: { id }', False),
    M('SaveAjusteInventario', 'Params: { id?, fecha, descripcion, items:[{articulo_codigo, bodega_codigo, cantidad_sistema, cantidad_fisica, costo_unitario}] }', True),
    M('ContabilizarAjuste', 'Params: { id } — genera movimientos e intenta comprobante contable', True),
    M('SaveSalidaInventario', 'Salida de inventario por consumo (dispensacion hospitalaria, consumo interno). A diferencia del ajuste (conteo fisico), el llamador declara cuanto salio y el ERP valoriza al costo promedio vigente de la bodega, escribe kardex y descuenta saldos en la misma transaccion. Params: { fecha?, descripcion, ref_externa?, items:[{articulo_codigo, bodega_codigo, cantidad, costo_unitario?}] } ref_externa es idempotente: si ya existe una salida con esa referencia para la empresa, se devuelve la existente sin duplicar movimientos.', True),
    M('SaveEntradaInventario', 'Entrada de inventario valorizada (compra de farmacia hospitalaria, ingreso de mercancia). Espejo de la salida: escribe kardex ENTRADA y sube saldos a costo promedio ponderado en una transaccion. La contrapartida contable NO la genera este metodo: la pone la factura AP (Db inventario / Cr proveedores) por el mismo valor. Params: { fecha?, descripcion, ref_externa?, proveedor_tipo_id?, proveedor_numero_id?, factura_proveedor?, items:[{articulo_codigo, bodega_codigo, cantidad, costo_unitario}] } ref_externa idempotente: la misma referencia no vuelve a subir stock.', True),
    M('GetConfigInventario', 'Configuración inventario', False),
    M('SaveConfigInventario', '', True)
  ];

  // Ventas (22 ops)
  GModules[18].Tool := 'conta_ventas';
  GModules[18].Title := 'Ventas';
  GModules[18].Desc := 'Facturas de venta, cotizaciones, remisiones, formas de pago y comisiones';
  GModules[18].Methods := [
    M('GetDocumentosVenta', 'Lista documentos de venta con filtros opcionales Params: { tipo_doc?, estado?, fecha_desde?, fecha_hasta?, tercero? (tambien busca por numero, p.ej. FEJV1), fe_estado? (PENDIENTE|RECHAZADA| ACEPTADA|SIN_CORREO), con_saldo? } Cada fila trae saldo (ver SqlSaldoVenta), notas que la afectan y, si es nota, la factura que afecta.', False),
    M('GetDocumentoVenta', 'Retorna un documento de venta con sus ítems Params: { id: int }', False),
    M('SaveDocumentoVenta', 'Crea o actualiza un documento de venta (cabecera + ítems) Params: { id?, tipo_doc, fecha, fecha_vencimiento?, tercero_tipo_id, tercero_numero_id, moneda_codigo, descripcion?, ref_externa?, centro_operacion_codigo?, items:[{linea, articulo_codigo, descripcion, bodega_codigo, cantidad, precio_unitario, descuento_pct, impuesto_pct}], pagos:[{forma_pago_id | forma_pago_nombre, valor}] } pagos: forma_pago_nombre se resuelve contra con_formas_pago del tenant (para integradores que no conocen los id); nombre desconocido = error. ref_externa (p.ej. ''CADUCEOS:miranda:12345'') hace la llamada idempotente: si ya existe un documento con esa referencia, en BORRADOR se actualiza y en cualquier otro estado se devuelve tal cual, sin crear un duplicado.', True),
    M('AnularDocumentoVenta', 'Anula un documento de venta (estado → ANULADO) Params: { id: int, motivo? }', True),
    M('FacturarDocumento', 'Convierte una cotización/pedido/remisión en factura Params: { id: int }', True),
    M('FacturarVenta', 'Facturar en un paso (estilo Siigo): envia (comision) + contabiliza Params: { id, comp_tipo? } — comp_tipo default desde config ventas', True),
    M('ContabilizarVenta', 'Contabiliza una factura de venta: genera comprobante y descuenta inventario Params: { id: int, comp_tipo: string }', True),
    M('EnviarDocumento', 'Cambia estado BORRADOR a ENVIADO; si FACTURA+vendedor genera comision automatica Params: { id: int }', True),
    M('GetVendedores', 'Lista usuarios activos de la empresa (para selector de vendedor)', False),
    M('GetMetasVentas', 'Metas de ventas por periodo con totales calculados Params: { periodo?: ''YYYY-MM'' }', False),
    M('SaveMetaVentas', 'Crea o actualiza meta de vendedor para un periodo Params: { id?, vendedor_login, periodo, meta_valor, porcentaje_comision }', True),
    M('GetComisionesVentas', 'Comisiones detalladas Params: { periodo?: ''YYYY-MM'', vendedor_login?: string }', False),
    M('GetResumenComisiones', 'Resumen de comisiones agrupado por vendedor Params: { periodo?: ''YYYY-MM'' }', False),
    M('PagarComision', 'Marca una comision como PAGADA Params: { id: int, notas? }', True),
    M('EnviarDocumentoWhatsApp', 'Envia resumen de documento por WhatsApp al celular del tercero (o al indicado) Params: { id: int, celular: string }', True),
    M('GetKPIVentas', 'KPI Dashboard ventas Params: { periodo?: ''YYYY-MM'' }', False),
    M('GetSolicitudesCompra', 'Solicitudes de compra (OC-1) Params: { estado?, fecha_desde?, fecha_hasta?, solicitante_login? }', False),
    M('GetSolicitudCompra', 'Params: { id }', False),
    M('SaveSolicitudCompra', 'Params: { id?, fecha, bodega_codigo?, notas?, items: [...] }', True),
    M('EnviarSolicitudCompra', 'Params: { id }', True),
    M('AprobarSolicitudCompra', 'Params: { id, notas? }', True),
    M('RechazarSolicitudCompra', 'Params: { id, motivo }', True)
  ];

  // Compras (15 ops)
  GModules[19].Tool := 'conta_compras';
  GModules[19].Title := 'Compras';
  GModules[19].Desc := 'Ordenes de compra, recepciones de mercancia y facturas de proveedor';
  GModules[19].Methods := [
    M('GetOrdenesCompra', 'Params: { estado?, fecha_desde?, fecha_hasta? }', False),
    M('GetOrdenCompra', 'Params: { id }', False),
    M('SaveOrdenCompra', 'Params: { id?, fecha, proveedor_tipo_id?, proveedor_numero_id?, proveedor_nombre?, fecha_entrega?, terminos_pago?, notas?, sc_id?, items[] }', True),
    M('EnviarOrdenCompra', 'Params: { id }', True),
    M('CancelarOrdenCompra', 'Params: { id }', True),
    M('CrearOCdesdeSC', 'Params: { sc_id } — crea OC desde SC aprobada y marca SC como CONVERTIDA', True),
    M('GetRecepcionesByOC', 'Params: { oc_id }', False),
    M('GetRecepcion', 'Params: { id }', False),
    M('SaveRecepcion', 'Params: { oc_id, fecha, notas?, items:[{oc_item_id, cantidad_recibida, notas_item?}] }', True),
    M('GetFacturasProveedor', 'Params: { estado?, fecha_desde?, fecha_hasta?, oc_id? }', False),
    M('GetFacturaProveedor', 'Params: { id }', False),
    M('SaveFacturaProveedor', 'Params: { id?, fecha, proveedor_tipo_id?, proveedor_numero_id?, proveedor_nombre?, oc_id?, numero_factura_prov?, fecha_vencimiento?, subtotal, iva, total, notas?, items[] }', True),
    M('AprobarFacturaProveedor', 'Params: { id } — realiza 3-way match y aprueba si pasa', True),
    M('RechazarFacturaProveedor', 'Params: { id, motivo }', True),
    M('GetDashboardCompras', 'Sin params — devuelve KPIs del modulo compras', False)
  ];

  // Cuentas por pagar (15 ops)
  GModules[20].Tool := 'conta_cuentas_pagar';
  GModules[20].Title := 'Cuentas por pagar';
  GModules[20].Desc := 'Cuentas por pagar (AP): causacion, pagos, saldos, vencimientos y anticipos/saldos a favor con proveedores';
  GModules[20].Methods := [
    M('GetSaldosAFavorProveedores', 'Mueve mercancia de una bodega a otra al mismo costo, en un paso. Params: { fecha?, bodega_origen, bodega_destino, notas?, items: [{ articulo_codigo, cantidad, unidad? }] }', False),
    M('GetAnticiposProveedor', 'Params: { tipo_id, numero_id } -> { saldo, movimientos }', False),
    M('AplicarAnticipoAP', 'Cruza el saldo a favor contra una factura. Params: { factura_id, valor, fecha? }', True),
    M('ReembolsoAnticipoAP', 'El proveedor devuelve el dinero. Params: { tipo_id, numero_id, valor, cuenta_banco_codigo, fecha?, notas? }', True),
    M('GetAPFacturas', 'Lista facturas de proveedores con filtros opcionales Params: { estado?, tercero?, vencidas? }', False),
    M('GetAPFactura', 'Retorna una factura de proveedor con sus ítems Params: { id: int }', False),
    M('SaveAPFactura', 'Crea o actualiza una factura de proveedor (cabecera + ítems) Params: { id?, tercero_tipo_id, tercero_numero_id, numero_factura_proveedor, fecha_factura, fecha_vencimiento, concepto?, ref_externa?, centro_operacion_codigo?, items:[{linea, descripcion, cuenta_gasto?, articulo_codigo?, cantidad, valor_unitario, impuesto_pct, retencion_pct}] } ref_externa hace la llamada idempotente (HIS): editable se actualiza, contabilizada/pagada se devuelve tal cual. Un item con articulo_codigo y sin cuenta_gasto debita la cuenta de INVENTARIO (la del articulo o la default de config inventario) — el kardex lo escribe CON_SaveEntradaInventario por el mismo valor.', True),
    M('AprobarAPFactura', 'Aprueba una factura de proveedor (RECIBIDA/REVISADA → APROBADA) Params: { id: int }', True),
    M('ContabilizarAPFactura', 'Contabiliza una factura de proveedor: genera comprobante contable Params: { id: int, comp_tipo: string }', True),
    M('AnularAPFactura', 'Anula una factura de proveedor (solo si no está contabilizada) Params: { id: int, motivo? }', True),
    M('GetAPPagos', 'Lista pagos a proveedores con filtros opcionales Params: { estado?, fecha_desde?, fecha_hasta? }', False),
    M('SaveAPPago', 'Crea o actualiza un pago a proveedores y aplica a facturas Params: { id?, fecha, forma_pago, cuenta_banco_codigo, numero_referencia?, notas?, facturas:[{factura_id, valor_aplicado}] }', True),
    M('ContabilizarAPPago', 'Contabiliza un pago a proveedor: genera comprobante contable Params: { id: int, comp_tipo: string }', True),
    M('GetConfigAP', 'Retorna configuración de AP', False),
    M('SaveConfigAP', 'Guarda configuración de AP (UPSERT) Params: { tipo_comprobante_ap, cuenta_proveedores, cuenta_iva_soportado, cuenta_retenciones }', True)
  ];

  // Tesoreria (10 ops)
  GModules[21].Tool := 'conta_tesoreria';
  GModules[21].Title := 'Tesoreria';
  GModules[21].Desc := 'Tesoreria: cajas, bancos, traslados y pagos';
  GModules[21].Methods := [
    M('GetCajas', 'Retorna cajas/cuentas de tesorería activas de la empresa Params: { nit_empresa }', False),
    M('SaveCaja', 'Crea o actualiza una caja/cuenta de tesorería Params: { codigo, nombre, tipo, moneda_codigo, cuenta_contable, banco_nombre, numero_cuenta, tipo_cuenta, saldo_inicial, saldo_actual, activa }', True),
    M('GetMovimientosTesoreria', 'Retorna movimientos de tesorería con filtros opcionales Params: { caja_codigo?, fecha_desde?, fecha_hasta?, estado? }', False),
    M('SaveMovimientoTesoreria', 'Registra un movimiento de tesorería (ENTRADA o SALIDA) Params: { caja_codigo, tipo, fecha, numero_documento, concepto, tercero_tipo_id?, tercero_numero_id?, valor, forma_pago?, referencia_externa? }', True),
    M('ContabilizarMovimiento', 'Contabiliza un movimiento de tesorería pendiente Params: { id, comp_tipo, cuenta_destino? }', True),
    M('GetProgramacionPagos', 'Retorna programación de pagos con filtros opcionales Params: { tipo?, estado?, fecha_desde?, fecha_hasta? }', False),
    M('SaveProgramacionPago', 'Crea o actualiza un registro de programación de pagos Params: { id?, fecha_programada, tipo, concepto, valor, caja_codigo, ap_factura_id?, venta_id?, tercero_tipo_id?, tercero_numero_id? }', True),
    M('EjecutarPago', 'Ejecuta un pago programado: genera movimiento de tesorería automático Params: { id }', True),
    M('SaveTransferencia', 'Crea o actualiza una transferencia entre cajas Params: { id?, fecha, caja_origen, caja_destino, valor, concepto, referencia? }', True),
    M('ContabilizarTransferencia', 'Contabiliza una transferencia entre cajas Params: { id, comp_tipo }', True)
  ];

  // Cobranza (24 ops)
  GModules[22].Tool := 'conta_cobranza';
  GModules[22].Title := 'Cobranza';
  GModules[22].Desc := 'Cobranza: cartera, recibos de caja, acuerdos de pago, estado de cuenta, provisiones, indicadores y saldos a favor/anticipos de clientes';
  GModules[22].Methods := [
    M('GetSaldosAFavorClientes', '', False),
    M('GetAnticiposCliente', 'Params: { numero_id } -> { saldo, movimientos }', False),
    M('AplicarAnticipoCliente', 'Cruza el saldo a favor contra una factura. Params: { documento_id, valor, fecha? }', True),
    M('DevolverAnticipoCliente', 'Se le devuelve el dinero. Params: { tipo_id, numero_id, valor, cuenta_caja, fecha?, tipo_comprobante?, notas? }', True),
    M('GetCarteraGestion', 'Retorna cartera (facturas) con saldo pendiente y datos de gestión Params: { solo_vencidas?, gestor_login? }', False),
    M('GetTareasCobranza', 'Retorna tareas de cobranza con filtros opcionales Params: { gestor_login?, tercero_numero_id?, resultado?, fecha_desde?, fecha_hasta? }', False),
    M('SaveTareaCobranza', 'Crea (id=0) o actualiza (id>0) una tarea de cobranza Params: { id?, tercero_tipo_id, tercero_numero_id, gestor_login, tipo, fecha_programada, fecha_ejecutada?, resultado, fecha_promesa_pago?, valor_prometido?, notas? }', True),
    M('GetConfigCobranza', 'Retorna la configuración de recordatorios para la empresa', False),
    M('SaveConfigCobranza', 'Guarda configuración de recordatorios (UPSERT) Params: { dias_antes_vencimiento, dias_despues_vencimiento, plantilla_email_previo?, plantilla_email_vencido?, activo }', True),
    M('EnviarRecordatorios', 'Procesa y registra recordatorios automáticos según config activa', True),
    M('GetRecibosCaja', 'Lista recibos de caja con filtros opcionales Params: { tercero_numero_id?, fecha_desde?, fecha_hasta?, estado? }', False),
    M('SaveReciboCaja', 'Crea (id=0) o actualiza (id>0) recibo con aplicaciones a facturas Params: { id?, fecha, tercero_tipo_id, tercero_numero_id, tercero_nombre?, concepto?, valor_total, forma_pago, banco?, numero_cheque?, referencia?, cuenta_caja?, ref_externa?, aplicaciones: [{documento_id, valor_aplicado}] } ref_externa hace la llamada idempotente para integradores (HIS): BORRADOR con la misma ref se actualiza; APLICADO/ANULADO se devuelve tal cual sin crear un recibo nuevo.', True),
    M('ContabilizarRecibo', 'Genera asiento contable (DEBE cuenta_caja / HABER cuenta_deudores) Params: { id, comp_tipo }', True),
    M('AnularRecibo', 'Anula un recibo en estado BORRADOR Params: { id }', True),
    M('GetAcuerdosPago', 'Lista acuerdos de pago con filtros opcionales Params: { tercero_numero_id?, estado?, fecha_desde?, fecha_hasta? }', False),
    M('SaveAcuerdoPago', 'Crea (id=0) o actualiza acuerdo con cuotas Params: { id?, fecha, tercero_tipo_id, tercero_numero_id, tercero_nombre?, concepto?, valor_total, num_cuotas, gestor_login?, notas?, cuotas: [{numero_cuota, fecha_vencimiento, valor}] }', True),
    M('GetCuotasAcuerdo', 'Retorna cuotas de un acuerdo Params: { acuerdo_id }', False),
    M('RegistrarPagoCuota', 'Marca una cuota como pagada y la vincula a un recibo Params: { cuota_id, recibo_id }', True),
    M('GetEstadoCuentaCliente', 'Retorna estado de cuenta de un cliente (facturas + recibos + saldos) Params: { tercero_numero_id }', False),
    M('GetProvisionConfig', 'Retorna la config de porcentajes de provisión por rango', False),
    M('SaveProvisionConfig', 'Guarda la config de porcentajes y cuentas contables para provisiones Params: { rangos: [{rango_dias, porcentaje, cuenta_provision?, cuenta_gasto?}] }', True),
    M('CalcularProvisiones', 'Calcula provisiones para un período según la cartera actual Params: { periodo } (YYYY-MM) — retorna filas con saldo y provision por rango', False),
    M('ContabilizarProvisionCartera', 'Contabiliza las provisiones de cartera de un período (DEBE gasto / HABER provision) Params: { periodo, comp_tipo }', True),
    M('GetIndicadoresCobranza', 'Retorna DSO, tasa recuperacion, mora promedio, facturas vencidas %', False)
  ];

  // Punto de venta (POS) (41 ops)
  GModules[23].Tool := 'conta_pos';
  GModules[23].Title := 'Punto de venta (POS)';
  GModules[23].Desc := 'POS: cajas, turnos, ventas rapidas, medios de pago y cierres';
  GModules[23].Methods := [
    M('GetTurnoActivo', 'Sin params — devuelve turno activo del usuario o vacio', False),
    M('AbrirTurno', 'Params: { saldo_inicial }', True),
    M('CerrarTurno', 'Params: { id, saldo_final?, notas? }', True),
    M('POSCobrar', 'Params: { turno_id, tipo_codigo, fecha, tercero_tipo_id?, tercero_numero_id?, forma_pago, efectivo_recibido?, items:[{articulo_codigo?,descripcion, cantidad,precio_unitario,descuento_pct,iva_pct}] }', True),
    M('GetMovimientosCaja', 'POS-2: Historial / movimientos / reporte de turno Params: { turno_id }', False),
    M('SaveMovimientoCaja', 'Params: { turno_id, tipo, concepto, monto }', True),
    M('GetVentasPOSByTurno', 'Params: { turno_id }', False),
    M('GetReporteCierreTurno', 'Params: { turno_id }', False),
    M('GetReportePOSDiario', 'POS-3: Reportes analíticos Params: { desde, hasta }', False),
    M('GetReportePOSHoras', 'Params: { desde, hasta }', False),
    M('GetTopProductosPOS', 'Params: { desde, hasta }', False),
    M('GetHistorialTurnos', 'Params: {}', False),
    M('GetBOMs', 'MFG-1: Lista de materiales (BOM) + Órdenes de producción Params: {}', False),
    M('GetBOM', 'Params: { id }', False),
    M('SaveBOM', 'Params: { id?, producto_codigo, cantidad_producida, notas?, items:[] }', True),
    M('GetOrdenesProduccion', 'Params: { estado? }', False),
    M('GetOrdenProduccion', 'Params: { id }', False),
    M('SaveOrdenProduccion', 'Params: { id?, bom_id?, producto_codigo, descripcion, cantidad_planificada, fecha_inicio?, fecha_fin_planificada?, bodega_destino_id?, notas?, materiales:[] }', True),
    M('IniciarOrdenProduccion', 'Params: { id }', True),
    M('CompletarOrdenProduccion', 'Params: { id, cantidad_producida }', True),
    M('CancelarOrdenProduccion', 'Params: { id }', True),
    M('GetResumenManufactura', 'MFG-3 Dashboard Params: { fecha_desde, fecha_hasta }', False),
    M('GetProduccionPeriodo', 'Params: { fecha_desde, fecha_hasta }', False),
    M('GetTopProductosProducidos', 'Params: { fecha_desde, fecha_hasta }', False),
    M('GenerarTokenPortal', 'Portal del cliente (publico — sin sesion requerida) Params: { tercero_tipo_id, tercero_numero_id }', True),
    M('GetPortalData', 'Params: { token } — SIN CheckSession', False),
    M('PortalGenerarPago', 'Params: { token, documento_id } — SIN CheckSession', True),
    M('GetConfigWompi', 'Wompi — pago en linea Params: {}', False),
    M('SaveConfigWompi', 'Params: { public_key, private_key, integrity_key, eventos_key, ambiente, activo }', True),
    M('GenerarPagoWompi', 'Params: { documento_id: int, redirect_url?: string }', True),
    M('ConsultarPagoWompi', 'Params: { documento_id: int }', True),
    M('GetListasPrecio', 'Lista de precios Params: {}', False),
    M('SaveListaPrecio', 'Crea o actualiza una lista de precios Params: { id?, nombre, moneda_codigo, activa, vigente_desde?, vigente_hasta? }', True),
    M('GetListaPrecioDetalle', 'Detalle de una lista de precio Params: { lista_id: int }', False),
    M('SaveListaPrecioDetalle', 'Guarda (reemplaza) el detalle completo de una lista de precio Params: { lista_id: int, detalle: [{articulo_codigo, precio_unitario, descuento_pct}] }', True),
    M('GetCondicionesCliente', 'Condiciones comerciales de un cliente (para pre-cargar en nuevo documento) Params: { tipo_id: string, numero_id: string }', False),
    M('GetConfigVentas', 'Configuración de ventas', False),
    M('SaveConfigVentas', 'Guarda configuración de ventas (UPSERT) Params: { tipo_comprobante_venta, cuenta_deudores_comerciales, cuenta_ventas, cuenta_iva_ventas, cuenta_descuentos, bodega_default }', True),
    M('GetFormasPago', 'Formas de pago (contado/credito estilo Siigo) Sin maneja_vencimiento => CONTADO (debito a cuenta_codigo caja/bancos) Con maneja_vencimiento => CREDITO (debito a deudores + vencimiento) Params GetFormasPago: { tipo?, solo_activas? }', False),
    M('SaveFormaPago', 'Params: { id?, nombre, tipo, cuenta_codigo, maneja_vencimiento, dias_vencimiento?, activa?, orden? }', True),
    M('ToggleFormaPago', 'Params: { id, activa }', True)
  ];

  // CRM y conversaciones (26 ops)
  GModules[24].Tool := 'conta_crm';
  GModules[24].Title := 'CRM y conversaciones';
  GModules[24].Desc := 'CRM: oportunidades, pipelines, campanas; mensajeria Twilio/WhatsApp y conversaciones';
  GModules[24].Methods := [
    M('GetProspectos', 'Retorna lista de prospectos con filtros opcionales Params: { estado?, asignado_a?, busqueda? }', False),
    M('SaveProspecto', 'Crea o actualiza un prospecto Params: { id?, nombre, empresa, cargo, email, telefono, ciudad, origen, estado, asignado_a, notas }', True),
    M('ConvertirProspecto', 'Convierte un prospecto en tercero Params: { id, tipo_id, numero_id }', True),
    M('GetOportunidades', 'Retorna lista de oportunidades con filtros opcionales Params: { etapa?, responsable? }', False),
    M('SaveOportunidad', 'Crea o actualiza una oportunidad Params: { id?, nombre, etapa, valor_estimado, probabilidad_pct, fecha_cierre_estimada?, responsable_login?, descripcion?, motivo_perdida?, tercero_tipo_id?, tercero_numero_id?, prospecto_id?, cotizacion_id?, moneda_codigo? }', True),
    M('GetActividadesCRM', 'Retorna lista de actividades CRM con filtros opcionales Params: { responsable?, estado?, oportunidad_id? }', False),
    M('SaveActividadCRM', 'Crea o actualiza una actividad CRM Params: { id?, tipo, asunto, fecha_programada?, fecha_realizada?, duracion_min?, responsable_login?, descripcion?, resultado?, estado?, tercero_tipo_id?, tercero_numero_id?, oportunidad_id?, prospecto_id? }', True),
    M('GetTwilioConfig', 'Retorna config Twilio del tenant (sin auth_token por seguridad)', False),
    M('SaveTwilioConfig', 'Guarda credenciales Twilio. auth_token solo se actualiza si viene en el payload. Params: { account_sid, auth_token?, sms_from, whatsapp_from, activo }', True),
    M('TestTwilio', 'Envia mensaje de prueba. Params: { canal: "SMS|WHATSAPP", destinatario: "+57..." }', True),
    M('EnviarSMS', 'Envia SMS. Params: { celular, mensaje }', True),
    M('EnviarWhatsApp', 'Envia WhatsApp. Params: { celular, mensaje }', True),
    M('GetConversaciones', 'Lista conversaciones con filtros opcionales. Params: { canal?, estado?, agente_login?, page?, page_size? }', False),
    M('GetMensajes', 'Retorna mensajes de una conversacion. Params: { conversacion_id }', False),
    M('EnviarMensaje', 'Envia mensaje saliente (WhatsApp o SMS) y lo persiste. Params: { conversacion_id, contenido }', True),
    M('CerrarConversacion', 'Cierra una conversacion. Params: { conversacion_id }', True),
    M('AsignarAgenteConv', 'Asigna agente a conversacion. Params: { conversacion_id, agente_login }', True),
    M('GetContacto360', '360 view', False),
    M('GetCampanas', 'Campanas masivas', False),
    M('SaveCampana', '', True),
    M('EnviarCampana', '', True),
    M('GetCampanaDetalle', '', False),
    M('GetPipeline', 'Pipeline configurables', False),
    M('SaveEtapa', '', True),
    M('DeleteEtapa', '', True),
    M('ReorderEtapas', '', True)
  ];
end;

function ContaModules: TArray<TContaModuleDef>;
begin
  if Length(GModules) = 0 then
    BuildModules;
  Result := GModules;
end;

end.
