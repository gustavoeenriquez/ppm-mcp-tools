unit MCPTool.Conta.Params;

// GENERADO por gen_params.py desde uConServerMethods.pas — no editar a mano.
// Parametros que lee cada operacion, sacados del fuente del servidor.
// Spec: "llave[!][:tipo],..."  ! = requerida; tipo s=string i=entero n=numero
// b=booleano a=arreglo o=objeto (sin tipo = libre). Completa = el metodo no
// lee mas llaves que estas (si es False, el MCP no rechaza llaves extra).

interface

type
  TContaParamDef = record
    Name: string;
    Tipo: Char;        // s i n b a o, o #0 si libre
    Requerida: Boolean;
  end;

  TContaParamSpec = record
    Encontrada: Boolean;
    Completa: Boolean;
    Recibe: Boolean;   // el metodo del servidor tiene argumento Params
    Params: TArray<TContaParamDef>;
  end;

function ContaParamsDe(const AOp: string): TContaParamSpec;

implementation

uses
  System.SysUtils, System.Generics.Collections;

type
  TSpecRaw = record
    Spec: string;
    Completa: Boolean;
    Recibe: Boolean;
  end;

var
  GSpecs: TDictionary<string, TSpecRaw> = nil;

procedure P(const AOp, ASpec: string; ACompleta, ARecibe: Boolean);
var
  R: TSpecRaw;
begin
  R.Spec := ASpec;
  R.Completa := ACompleta;
  R.Recibe := ARecibe;
  GSpecs.AddOrSetValue(LowerCase(AOp), R);
end;

procedure Build;
begin
  GSpecs := TDictionary<string, TSpecRaw>.Create;
  P('GetVersion', '', True, False);
  P('GetMiPerfil', '', True, False);
  P('GetPaises', '', True, False);
  P('GetMonedas', '', True, False);
  P('GetGruposNIIF', '', True, False);
  P('GetTiposCuenta', '', True, False);
  P('GetTiposIdentificacion', 'pais_codigo:s', True, True);
  P('GetMisEmpresas', '', True, False);
  P('GetConsolidado', 'anio:i,mes:i,empresas:a', True, True);
  P('GetAuditLog', 'fecha_desde:s,fecha_hasta:s,usuario:s,tabla:s,limit:i', True, True);
  P('GetNotificaciones', '', True, False);
  P('GetEmpresa', '', True, False);
  P('SaveEmpresa', 'razon_social:s,pais_codigo:s,moneda_codigo:s,grupo_niif:i,decimales:i,anio_fiscal_mes:i,fev_url:s,co_obligatorio:b,requiere_aprobacion:b,responsable_iva:b,ne_municipio_dane:s,ne_direccion:s,ne_metodo_pago:s,fev_api_key', True, True);
  P('CrearEmpresa', 'nit_empresa:s,razon_social!:s,pais_codigo:s,moneda_codigo:s,grupo_niif:i,decimales:i,anio_fiscal_mes!:i,sembrar:b,responsable_iva:b,admin_login:s,admin_nombre:s,admin_email:s,admin_password', True, True);
  P('GetUsuarios', '', True, False);
  P('SaveUsuario', 'login:s,nombre!:s,email:s,perfil:s,activo:b,centro_operacion_default:s,es_servicio:b,password', True, True);
  P('ChangePassword', 'password_actual:s,password_nueva:s', True, True);
  P('GetPermisos', 'login:s', True, True);
  P('SavePermisos', 'login:s,permisos', True, True);
  P('GetConfigEmail', '', True, False);
  P('SaveConfigEmail', 'smtp_host:s,smtp_port:i,smtp_usuario:s,smtp_password:s,smtp_ssl:b,remitente_email:s,remitente_nombre:s,activo:b', True, True);
  P('TestEmail', '', True, True);
  P('EnviarResumenPeriodo', 'anio!:i,mes!:i', True, True);
  P('GetSuscriptores', '', True, False);
  P('SaveSuscriptor', 'email:s,nombre:s,activo:b', True, True);
  P('DeleteSuscriptor', 'id!:i', True, True);
  P('GetConfigCuentas', '', True, False);
  P('SaveConfigCuenta', 'concepto!:s,cuenta_codigo!:s,descripcion:s', True, True);
  P('DeleteConfigCuenta', 'concepto:s', True, True);
  P('GetPucMaestro', 'pais:s', True, True);
  P('ImportarPucMaestro', 'pais!:s,nivel_max!:i', True, True);
  P('GetPlanCuentas', 'solo_activas:b,acepta_movto:b,nivel_max:i,buscar:s', True, True);
  P('GetCuenta', 'codigo!:s', True, True);
  P('SaveCuenta', 'codigo!:s,nombre!:s,tipo_cuenta:s,codigo_padre:s,es_nuevo:b,acepta_movto:b,requiere_tercero:b,requiere_centro_costo:b,requiere_documento:b,activa:b', True, True);
  P('DeleteCuenta', 'codigo!:s', True, True);
  P('GetTerceros', 'buscar:s,es_cliente:b,es_proveedor:b,page:i,page_size:i', True, True);
  P('GetTercero', 'tipo_id:s,numero_id:s', True, True);
  P('SaveTercero', 'tipo_id!:s,numero_id!:s,digito_verif:s,razon_social!:s,nombre_comercial:s,es_cliente:b,es_proveedor:b,es_empleado:b,roles_aditivos:b,email:s,telefono:s,direccion:s,ciudad:s,pais_codigo:s,tipo_persona:s,lista_precio_id:i,descuento_pct_habitual:n,dias_credito:i,limite_credito:n,municipio_dane:s', True, True);
  P('GetPlantillas', '', True, False);
  P('SavePlantilla', 'id:i,nombre:s,comp_tipo:s,descripcion:s,activa:b,movimientos:a', True, True);
  P('DeletePlantilla', 'id!:i', True, True);
  P('AplicarPlantilla', 'id!:i,fecha:s,descripcion:s,centro_operacion_codigo:s', True, True);
  P('GetTiposComprobante', '', True, False);
  P('SaveTipoComprobante', 'codigo!:s,nombre:s,prefijo:s,numeracion_auto:b,permite_edicion:b,activo:b', True, True);
  P('GetComprobantes', 'tipo_codigo:s,estado:s,buscar:s,fecha_desde:s,fecha_hasta:s,centro_operacion_codigo:s,page:i,page_size:i', True, True);
  P('GetComprobante', 'tipo_codigo!:s,numero!:i', True, True);
  P('SaveComprobante', 'tipo_codigo:s,fecha:s,descripcion:s,ref_tipo:s,ref_numero:s,centro_operacion_codigo:s,movimientos:a', True, True);
  P('ContabilizarComprobante', 'tipo_codigo!:s,numero!:i', True, True);
  P('AnularComprobante', 'tipo_codigo!:s,numero!:i', True, True);
  P('RevisarComprobante', 'tipo_codigo!:s,numero!:i,comentario:s', True, True);
  P('RechazarComprobante', 'tipo_codigo!:s,numero!:i,motivo!:s', True, True);
  P('GetPeriodos', 'anio:i', True, True);
  P('AbrirPeriodo', 'anio:i,mes!:i', True, True);
  P('CerrarPeriodo', 'anio!:i,mes!:i', True, True);
  P('GetCierresAnuales', '', True, False);
  P('ValidarCierreAnio', 'anio:i', True, True);
  P('CerrarAnio', 'anio:i', True, True);
  P('GetRetenciones', 'solo_activas:b', True, True);
  P('SaveRetencion', 'codigo!:s,nombre!:s,tipo:s,base_calculo:s,tarifa:n,cuenta_debito:s,cuenta_credito:s,activo:b', True, True);
  P('DeleteRetencion', 'codigo:s', True, True);
  P('GetRetencionesTercero', 'tipo_id:s,numero_id!:s', True, True);
  P('GetRetencionSugerida', 'tercero_tipo_id!:s,tercero_numero_id!:s,base_gravable!:n', True, True);
  P('SaveRetencionesTercero', 'tipo_id!:s,numero_id!:s,retenciones:a', True, True);
  P('RPT_Retenciones', 'anio:i,mes_desde:i,mes_hasta:i', True, True);
  P('GetCentrosCosto', 'solo_activos:b', True, True);
  P('SaveCentroCosto', 'codigo!:s,nombre!:s,codigo_padre:s,activo:b', True, True);
  P('DeleteCentroCosto', 'codigo:s', True, True);
  P('RPT_CentroCosto', 'anio:i,mes_desde:i,mes_hasta:i,centro_costo_codigo:s', True, True);
  P('RPT_PyGCentroCosto', 'anio:i,mes_desde:i,mes_hasta:i', True, True);
  P('RPT_BalancePrueba', 'anio:i,mes_desde:i,mes_hasta:i,centro_operacion_codigo:s', True, True);
  P('RPT_LibroDiario', 'anio:i,mes:i,tipo_codigo:s,fecha_desde:s,fecha_hasta:s,centro_operacion_codigo:s', True, True);
  P('RPT_LibroMayor', 'cuenta_codigo!:s,centro_operacion_codigo:s,anio:i,mes_desde:i,mes_hasta:i', True, True);
  P('RPT_BalanceGeneral', 'anio:i,mes:i', True, True);
  P('RPT_EstadoResultados', 'anio:i,mes_desde:i,mes_hasta:i,centro_operacion_codigo:s', True, True);
  P('RPT_Cartera', 'tipo:s,fecha_corte:s,tercero_numero_id:s', True, True);
  P('RPT_CarteraPorCuenta', 'tipo:s,fecha_corte:s,cuenta_desde:s,cuenta_hasta:s', True, True);
  P('RPT_CertificadoRetencion', 'anio:i,tercero_tipo_id:s,tercero_numero_id!:s', True, True);
  P('GetTRM', 'moneda_codigo:s,fecha_desde:s,fecha_hasta:s', True, True);
  P('SaveTRM', 'moneda_codigo!:s,fecha!:s,tasa!:n,fuente:s', True, True);
  P('DeleteTRM', 'moneda_codigo:s,fecha:s', True, True);
  P('GetTRMVigente', 'moneda_codigo!:s,fecha:s', True, True);
  P('AjusteDiferenciaCambio', 'anio!:i,mes!:i,comp_tipo!:s', True, True);
  P('ImportarTRMBanRep', 'fecha_desde:s,fecha_hasta:s', True, True);
  P('RPT_Dashboard', 'anio:i,mes:i', True, True);
  P('ImportarComprobantes', 'comprobantes:a', True, True);
  P('RPT_LibroIVA', 'anio:i,mes_desde:i,mes_hasta:i,prefijo_cuenta:s', True, True);
  P('RPT_LibroTercero', 'anio:i,mes_desde:i,mes_hasta:i,cuenta_desde:s,cuenta_hasta:s,tercero_id:s', True, True);
  P('RPT_BalanceComprobacion', 'anio:i,mes_desde:i,mes_hasta:i,niveles:s', True, True);
  P('RPT_AnalisisHorizontal', 'anio_a:i,mes_desde_a:i,mes_hasta_a:i,anio_b:i,mes_desde_b:i,mes_hasta_b:i', True, True);
  P('GetActivosFijos', '', True, False);
  P('SaveActivoFijo', 'codigo!:s,vida_util_meses!:i,valor_adquisicion:n,valor_residual:n,descripcion:s,categoria:s,fecha_adquisicion:s,metodo:s,cuenta_activo:s,cuenta_dep_acum:s,cuenta_gasto_dep:s,activo:b', True, True);
  P('DeleteActivoFijo', 'codigo:s', True, True);
  P('PreviewDepreciacion', 'anio:i,mes:i', True, True);
  P('EjecutarDepreciacion', 'anio:i,mes:i', True, True);
  P('BajaActivoFijo', 'codigo!:s,fecha_baja:s,tipo_baja:s,valor_venta:n,cuenta_destino:s,cuenta_resultado!:s,anio:i,mes:i', True, True);
  P('RevaluarActivoFijo', 'codigo!:s,nuevo_valor!:n,cuenta_ajuste!:s,anio:i,mes:i', True, True);
  P('GetHistorialDepreciaciones', '', True, False);
  P('GetPresupuestos', '', True, False);
  P('SavePresupuesto', 'anio:i,descripcion:s,estado:s', True, True);
  P('DeletePresupuesto', 'anio!:i', True, True);
  P('GetPresupuestoDetalle', 'anio:i', True, True);
  P('SavePresupuestoDetalle', 'anio:i,lineas:a', True, True);
  P('ImportarPresupuesto', 'filas:a', True, True);
  P('RPT_PresupuestoVsReal', 'anio:i,mes_hasta:i', True, True);
  P('GetConciliaciones', '', True, False);
  P('IniciarConciliacion', 'cuenta_codigo:s,anio:i,mes:i,saldo_extracto:n', True, True);
  P('GetMovtosConciliacion', 'conciliacion_id:i', True, True);
  P('MarcarMovtoConciliado', 'conciliacion_id!:i,comp_tipo:s,comp_numero:i,linea:i,conciliado:b', True, True);
  P('GetExtractoItems', 'conciliacion_id!:i', True, True);
  P('SaveExtractoItems', 'conciliacion_id:i,items:a', True, True);
  P('MarcarExtractoConciliado', 'conciliacion_id:i,item_id:i,conciliado:b', True, True);
  P('CerrarConciliacion', 'conciliacion_id:i', True, True);
  P('ReabrirConciliacion', 'conciliacion_id:i', True, True);
  P('GetExtractos', '', True, False);
  P('SaveExtracto', 'cuenta_codigo!:s,nombre_archivo:s,lineas:a', True, True);
  P('GetExtractoLineas', 'extracto_id:i', True, True);
  P('DeleteExtracto', 'extracto_id!:i', True, True);
  P('DeleteProvisiones', 'anio!:i,mes!:i', True, True);
  P('GetConfigEFE', '', True, False);
  P('SaveConfigEFE', 'cuenta_codigo!:s,seccion:s,orden:i,nombre_linea!:s,signo:i', True, True);
  P('DeleteConfigEFE', 'cuenta_codigo!:s', True, True);
  P('RPT_FlujoEfectivo', 'anio:i,mes:i', True, True);
  P('GetExogenaConceptos', 'anio:i', True, True);
  P('SaveExogenaConcepto', 'anio:i,concepto!:s,descripcion:s,cuenta_desde!:s,cuenta_hasta!:s,naturaleza_mov:s,umbral:n,activo:b', True, True);
  P('DeleteExogenaConcepto', 'anio!:i,concepto!:s', True, True);
  P('GenerarExogena', 'anio:i', True, True);
  P('GetExogenaResultado', 'anio:i,concepto:s', True, True);
  P('GetFacturasPendientesFEV', '', False, True);
  P('ContabilizarFacturaFEV', 'cufe!:s', True, True);
  P('EmitirFacturaElectronica', 'documento_id!:i', False, True);
  P('GetFEDocumentos', '', False, True);
  P('ConsultarEstadoFE', 'cufe!:s', False, True);
  P('GetFEConfig', '', False, False);
  P('SaveFEConfig', 'software_id:s,software_pin:s,cert_pfx_ruta:s,cert_password:s,cert_vence:s,ambiente:s,set_pruebas_id:s', True, True);
  P('GetFEResoluciones', '', False, True);
  P('SaveFEResolucion', 'id:i,prefijo:s,numero_desde:i,numero_hasta:i,numero_actual:i,fecha_desde!:s,fecha_hasta!:s,clave_tecnica:s,tipo_doc:s,ambiente:s,activa:b,numero_resolucion:s', True, True);
  P('DeleteFEResolucion', 'id!:i', True, True);
  P('GetEventosRadian', 'cufe!:s', True, True);
  P('GetNotasReferencia', 'cufe!:s', True, True);
  P('GetAdquirienteFEV', 'nit!:s,tipo_id:s', True, True);
  P('ProcesarPendientesFE', '', False, True);
  P('GetDocumentosParaEmitirFE', '', False, True);
  P('ImportarTerceros', 'terceros:a', True, True);
  P('ImportarArticulos', 'articulos:a', True, True);
  P('ImportarCuentas', 'cuentas:a', True, True);
  P('ImportarCentrosCosto', 'centros:a', True, True);
  P('ImportarActivosFijos', 'activos:a', True, True);
  P('ImportarNovedades', 'novedades:a', True, True);
  P('ImportarRetenciones', 'retenciones:a', True, True);
  P('ImportarSaldosInventario', 'saldos:a', True, True);
  P('GetEmpleados', '', True, False);
  P('SaveEmpleado', 'tipo_id:s,numero_id:s,nombres:s,apellidos:s,cargo:s,fecha_ingreso:s,salario_basico:n,tipo_contrato:s,dias_trabajados_mes:i,cuenta_salarios:s,cuenta_prestaciones:s,cuenta_aportes_emp:s,cuenta_pagar_emp:s,cuenta_pagar_seg:s,activo:b,nivel_riesgo_arl:i,ne_tipo_trabajador:s,ne_subtipo_trabajador:s,salario_integral:b,alto_riesgo_pension:b', True, True);
  P('ImportarEmpleados', 'empleados:a', True, True);
  P('GetNovedades', 'anio!:i,mes!:i,empleado_tipo_id:s,empleado_numero_id:s', True, True);
  P('SaveNovedad', 'id:i,anio!:i,mes!:i,empleado_tipo_id!:s,empleado_numero_id!:s,tipo_novedad!:s,dias!:i,descripcion:s', True, True);
  P('DeleteNovedad', 'id!:i', True, True);
  P('GetDescuentos', 'empleado_tipo_id:s,empleado_numero_id:s,solo_activos:b', True, True);
  P('SaveDescuento', 'id:i,empleado_tipo_id!:s,empleado_numero_id!:s,tipo_descuento!:s,descripcion!:s,valor_mensual!:n,activo:b,fecha_inicio:s,fecha_fin:s', True, True);
  P('DeleteDescuento', 'id!:i', True, True);
  P('GetNominas', '', True, False);
  P('GetDashboardNomina', 'anio:i', True, True);
  P('LiquidarNomina', 'anio:i,mes:i', True, True);
  P('GetNominaDetalle', 'nomina_id:i', True, True);
  P('UpdateNominaEmpleado', 'nomina_id:i,empleado_tipo_id:s,empleado_numero_id:s,horas_extras:n,otros_devengados:n,otras_deducciones:n', True, True);
  P('ContabilizarNomina', 'nomina_id:i', True, True);
  P('LiquidarProvisiones', 'anio!:i,mes!:i', True, True);
  P('GetProvisiones', 'anio:i,mes:i', True, True);
  P('ContabilizarProvisiones', 'anio!:i,mes!:i,comp_tipo:s', True, True);
  P('GetAcumuladoNomina', 'anio!:i,empleado_tipo_id:s,empleado_numero_id:s', True, True);
  P('GetCertificado220', 'anio!:i,empleado_tipo_id!:s,empleado_numero_id!:s', True, True);
  P('LiquidacionDefinitiva', 'empleado_tipo_id!:s,empleado_numero_id!:s,fecha_retiro!:s,causa_retiro:s', True, True);
  P('GetConceptosNomina', '', True, True);
  P('SaveConceptoNomina', 'id:i,codigo!:s,nombre!:s,tipo!:s,es_constitutivo:b,porcentaje:n,activo:b', True, True);
  P('IniciarConceptosNomina', '', True, True);
  P('GetEmpConceptos', 'nomina_id:i,empleado_tipo_id:s,empleado_numero_id:s', True, True);
  P('SaveEmpConcepto', 'nomina_id!:i,empleado_tipo_id!:s,empleado_numero_id!:s,concepto_codigo!:s,monto:n,id:i', True, True);
  P('DeleteEmpConcepto', 'id!:i,nomina_id:i,empleado_tipo_id:s,empleado_numero_id:s', True, True);
  P('GetCategoriasInv', '', True, True);
  P('SaveCategoriaInv', 'id:i,nombre!:s,codigo_padre:i', True, True);
  P('GetArticulos', 'buscar:s,tipo:s,activo:b', True, True);
  P('GetArticulo', 'codigo!:s', True, True);
  P('SaveArticulo', 'codigo!:s,nombre!:s,tipo:s,unidad_medida:s,metodo_costeo:s,maneja_inventario:b,bodega_codigo:s,precio_venta_default:n,impuesto_pct:n,tarifa_iva:s,categoria_id:i,cuenta_inventario:s,cuenta_costo_ventas:s,cuenta_ventas:s,unidades:a', True, True);
  P('DeleteArticulo', 'codigo!:s', True, True);
  P('GetBodegas', 'solo_activas:b', True, True);
  P('SaveBodega', 'codigo!:s,nombre!:s,responsable:s,activa:b', True, True);
  P('GetSaldosInventario', 'bodega_codigo:s,articulo_codigo:s,buscar:s', True, True);
  P('GetKardex', 'articulo_codigo!:s,bodega_codigo:s,fecha_desde:s,fecha_hasta:s', True, True);
  P('GetAjustesInventario', 'estado:s', True, True);
  P('GetAjusteInventario', 'id!:i', True, True);
  P('SaveAjusteInventario', 'id:i,fecha:s,descripcion!:s,items', True, True);
  P('ContabilizarAjuste', 'id!:i', True, True);
  P('GetConfigInventario', '', True, False);
  P('SaveConfigInventario', 'cuenta_inventario_default:s,cuenta_costo_ventas_default:s,cuenta_ajuste_inventario:s,bodega_default:s,tipo_comprobante_ajuste:s,permite_saldo_negativo:b,cuenta_ajuste_faltante:s,cuenta_ajuste_sobrante:s,cuenta_productos_proceso:s,tipo_comprobante_produccion:s', True, True);
  P('GetDocumentosVenta', 'tipo_doc:s,estado:s,fecha_desde:s,fecha_hasta:s,tercero:s,fe_estado:s,con_saldo:b', True, True);
  P('GetDocumentoVenta', 'id!:i', True, True);
  P('SaveDocumentoVenta', 'id:i,tipo_doc:s,fecha:s,fecha_vencimiento:s,tercero_tipo_id:s,tercero_numero_id:s,ref_externa:s,centro_operacion_codigo:s,sucursal_codigo:s,moneda_codigo:s,notas:s,descripcion:s,vendedor_login:s,items:a,pagos:a,ref_documento_id:i,ref_fe_numero:s,ref_fe_cufe:s,ref_fe_fecha:s,fe_concepto_nota:i,devuelve_mercancia:b', True, True);
  P('AnularDocumentoVenta', 'id!:i,motivo:s', True, True);
  P('FacturarDocumento', 'id!:i', True, True);
  P('FacturarVenta', 'id!:i,comp_tipo:s', True, True);
  P('ContabilizarVenta', 'id!:i,comp_tipo:s', True, True);
  P('EnviarDocumento', 'id!:i', True, True);
  P('GetVendedores', '', True, False);
  P('GetMetasVentas', 'periodo:s', True, True);
  P('SaveMetaVentas', 'id:i,vendedor_login!:s,periodo!:s,meta_valor:n,porcentaje_comision:n', True, True);
  P('GetComisionesVentas', 'periodo:s,vendedor_login:s', True, True);
  P('GetResumenComisiones', 'periodo:s', True, True);
  P('PagarComision', 'id!:i,notas:s', True, True);
  P('EnviarDocumentoWhatsApp', 'id!:i,celular!:s', True, True);
  P('GetKPIVentas', 'periodo:s', True, True);
  P('GetSolicitudesCompra', 'estado:s,fecha_desde:s,fecha_hasta:s,solicitante_login:s', True, True);
  P('GetSolicitudCompra', 'id!:i', True, True);
  P('SaveSolicitudCompra', 'id:i,fecha:s,bodega_codigo:s,notas:s,items:a', True, True);
  P('EnviarSolicitudCompra', 'id!:i', True, True);
  P('AprobarSolicitudCompra', 'id!:i,notas:s', True, True);
  P('RechazarSolicitudCompra', 'id!:i,motivo!:s', True, True);
  P('GetOrdenesCompra', 'estado:s,fecha_desde:s,fecha_hasta:s', True, True);
  P('GetOrdenCompra', 'id!:i', True, True);
  P('SaveOrdenCompra', 'id:i,fecha:s,proveedor_tipo_id:s,proveedor_numero_id:s,proveedor_nombre:s,fecha_entrega:s,terminos_pago:s,notas:s,sc_id:i,items!:a', True, True);
  P('EnviarOrdenCompra', 'id!:i', True, True);
  P('CancelarOrdenCompra', 'id!:i', True, True);
  P('CrearOCdesdeSC', 'sc_id!:i', True, True);
  P('GetRecepcionesByOC', 'oc_id!:i', True, True);
  P('GetRecepcion', 'id!:i', True, True);
  P('SaveRecepcion', 'oc_id!:i,fecha!:s,notas:s,items:a', True, True);
  P('GetFacturasProveedor', 'estado:s,fecha_desde:s,fecha_hasta:s,oc_id:i', True, True);
  P('GetFacturaProveedor', 'id!:i', True, True);
  P('SaveFacturaProveedor', 'id:i,fecha:s,proveedor_tipo_id:s,proveedor_numero_id:s,proveedor_nombre:s,oc_id:i,numero_factura_prov:s,fecha_vencimiento:s,subtotal:n,iva:n,total!:n,notas:s,items:a', True, True);
  P('AprobarFacturaProveedor', 'id!:i', True, True);
  P('RechazarFacturaProveedor', 'id!:i,motivo!:s', True, True);
  P('GetDashboardCompras', '', True, True);
  P('GetAPFacturas', 'estado:s,tercero:s,vencidas:b', True, True);
  P('GetAPFactura', 'id!:i', True, True);
  P('SaveAPFactura', 'id:i,tercero_tipo_id:s,tercero_numero_id:s,numero_factura_proveedor:s,fecha_factura:s,fecha_vencimiento:s,concepto:s,ref_externa:s,centro_operacion_codigo:s,sucursal_codigo:s,items:a,es_documento_soporte:b,ds_procedencia:s,ds_tipo:s,ref_ap_factura_id:i,fe_concepto_nota:i,es_nota_credito:b', True, True);
  P('AprobarAPFactura', 'id!:i', True, True);
  P('ContabilizarAPFactura', 'id!:i,comp_tipo:s', True, True);
  P('AnularAPFactura', 'id!:i,motivo:s', True, True);
  P('GetAPPagos', 'estado:s,fecha_desde:s,fecha_hasta:s', True, True);
  P('SaveAPPago', 'id:i,fecha:s,forma_pago:s,cuenta_banco_codigo:s,numero_referencia:s,notas:s,facturas:a', True, True);
  P('ContabilizarAPPago', 'id!:i,comp_tipo:s', True, True);
  P('GetConfigAP', '', True, False);
  P('SaveConfigAP', 'tipo_comprobante_factura_proveedor:s,tipo_comprobante_pago:s,cuenta_proveedores:s,cuenta_anticipos_proveedores:s,dias_alerta_vencimiento:i,cuenta_recibido_por_facturar:s', True, True);
  P('GetCajas', '', True, True);
  P('SaveCaja', 'codigo!:s,nombre!:s,tipo:s,moneda_codigo:s,cuenta_contable:s,banco_nombre:s,numero_cuenta:s,tipo_cuenta:s,saldo_inicial:n,saldo_actual:n,activa:b', True, True);
  P('GetMovimientosTesoreria', 'caja_codigo:s,fecha_desde:s,fecha_hasta:s,estado:s', True, True);
  P('SaveMovimientoTesoreria', 'caja_codigo!:s,tipo!:s,fecha!:s,numero_documento:s,concepto:s,tercero_tipo_id:s,tercero_numero_id:s,valor!:n,forma_pago:s,referencia_externa:s,centro_operacion_codigo:s', True, True);
  P('ContabilizarMovimiento', 'id:i,comp_tipo!:s,cuenta_destino:s,cuenta_origen!:s', True, True);
  P('GetProgramacionPagos', 'tipo:s,estado:s,fecha_desde:s,fecha_hasta:s', True, True);
  P('SaveProgramacionPago', 'id:i,fecha_programada!:s,tipo!:s,concepto:s,valor:n,caja_codigo!:s,ap_factura_id:i,venta_id:i,tercero_tipo_id:s,tercero_numero_id:s', True, True);
  P('EjecutarPago', 'id!:i', True, True);
  P('SaveTransferencia', 'id:i,fecha!:s,caja_origen!:s,caja_destino!:s,valor!:n,concepto:s,referencia:s', True, True);
  P('ContabilizarTransferencia', 'id!:i,comp_tipo!:s', True, True);
  P('GetCarteraGestion', 'solo_vencidas:b,gestor_login:s', True, True);
  P('GetTareasCobranza', 'gestor_login:s,tercero_numero_id:s,resultado:s,fecha_desde:s,fecha_hasta:s', True, True);
  P('SaveTareaCobranza', 'id:i,tercero_tipo_id:s,tercero_numero_id:s,gestor_login:s,tipo:s,fecha_programada!:s,fecha_ejecutada:s,resultado:s,fecha_promesa_pago:s,valor_prometido:n,notas:s', True, True);
  P('GetConfigCobranza', '', True, False);
  P('SaveConfigCobranza', 'dias_antes_vencimiento:s,dias_despues_vencimiento:s,plantilla_email_previo:s,plantilla_email_vencido:s,activo:b', True, True);
  P('EnviarRecordatorios', '', True, False);
  P('GetRecibosCaja', 'tercero_numero_id:s,fecha_desde:s,fecha_hasta:s,estado:s', True, True);
  P('SaveReciboCaja', 'id:i,tercero_tipo_id:s,tercero_numero_id!:s,tercero_nombre:s,fecha!:s,concepto:s,valor_total!:n,ref_externa:s,centro_operacion_codigo:s,forma_pago:s,banco:s,numero_cheque:s,referencia:s,cuenta_caja:s,es_anticipo:b,aplicaciones:a', True, True);
  P('ContabilizarRecibo', 'id!:i,comp_tipo:s', True, True);
  P('AnularRecibo', 'id!:i', True, True);
  P('GetAcuerdosPago', 'tercero_numero_id:s,estado:s,fecha_desde:s,fecha_hasta:s', True, True);
  P('SaveAcuerdoPago', 'id:i,tercero_tipo_id:s,tercero_numero_id!:s,tercero_nombre:s,fecha!:s,concepto:s,valor_total!:n,num_cuotas:i,estado:s,gestor_login:s,notas:s,cuotas:a', True, True);
  P('GetCuotasAcuerdo', 'acuerdo_id!:i', True, True);
  P('RegistrarPagoCuota', 'cuota_id!:i,recibo_id:i', True, True);
  P('GetEstadoCuentaCliente', 'tercero_numero_id!:s', True, True);
  P('GetProvisionConfig', '', True, False);
  P('SaveProvisionConfig', 'rangos:a', True, True);
  P('CalcularProvisiones', 'periodo:s', True, True);
  P('ContabilizarProvisionCartera', 'periodo:s,comp_tipo:s', True, True);
  P('GetIndicadoresCobranza', '', True, False);
  P('GetTurnoActivo', '', True, True);
  P('AbrirTurno', 'saldo_inicial:n', True, True);
  P('CerrarTurno', 'id!:i,saldo_final:n,notas:s', True, True);
  P('POSCobrar', 'turno_id:i,fecha:s,tercero_tipo_id:s,tercero_numero_id:s,forma_pago:s,forma_pago_id:i,efectivo_recibido:n,items:a', True, True);
  P('GetMovimientosCaja', 'turno_id!:i', True, True);
  P('SaveMovimientoCaja', 'turno_id!:i,tipo!:s,concepto!:s,monto!:n', True, True);
  P('GetVentasPOSByTurno', 'turno_id!:i', True, True);
  P('GetReporteCierreTurno', 'turno_id!:i', True, True);
  P('GetReportePOSDiario', 'desde!:s,hasta!:s', True, True);
  P('GetReportePOSHoras', 'desde!:s,hasta!:s', True, True);
  P('GetTopProductosPOS', 'desde!:s,hasta!:s', True, True);
  P('GetHistorialTurnos', '', True, True);
  P('GetBOMs', '', True, True);
  P('GetBOM', 'id!:i', True, True);
  P('SaveBOM', 'id:i,producto_codigo!:s,cantidad_producida:n,notas:s,items!:a', True, True);
  P('GetOrdenesProduccion', 'estado:s', True, True);
  P('GetOrdenProduccion', 'id!:i', True, True);
  P('SaveOrdenProduccion', 'id:i,bom_id:i,bodega_destino_codigo:s,fecha_inicio:s,fecha_fin_planificada:s,producto_codigo!:s,descripcion!:s,cantidad_planificada!:n,notas:s,bodega_origen_codigo:s,materiales!:a', True, True);
  P('IniciarOrdenProduccion', 'id:i', True, True);
  P('CompletarOrdenProduccion', 'id:i,cantidad_producida!:n', True, True);
  P('CancelarOrdenProduccion', 'id:i', True, True);
  P('GetResumenManufactura', 'fecha_desde!:s,fecha_hasta!:s', True, True);
  P('GetProduccionPeriodo', 'fecha_desde!:s,fecha_hasta!:s', True, True);
  P('GetTopProductosProducidos', 'fecha_desde!:s,fecha_hasta!:s', True, True);
  P('GenerarTokenPortal', 'tercero_tipo_id!:s,tercero_numero_id!:s', True, True);
  P('GetPortalData', 'token!:s', True, True);
  P('PortalGenerarPago', 'token!:s,documento_id!:i', True, True);
  P('GetConfigWompi', '', True, True);
  P('SaveConfigWompi', 'public_key:s,private_key:s,integrity_key:s,eventos_key:s,ambiente:s,activo:b', True, True);
  P('GenerarPagoWompi', 'documento_id!:i,redirect_url:s', True, True);
  P('ConsultarPagoWompi', 'documento_id!:i', True, True);
  P('GetListasPrecio', '', True, True);
  P('SaveListaPrecio', 'id:i,nombre!:s,moneda_codigo:s,activa:b,vigente_desde:s,vigente_hasta:s', True, True);
  P('GetListaPrecioDetalle', 'lista_id!:i', True, True);
  P('SaveListaPrecioDetalle', 'lista_id:i,detalle:a', True, True);
  P('GetCondicionesCliente', 'tipo_id:s,numero_id:s', True, True);
  P('GetConfigVentas', '', True, False);
  P('SaveConfigVentas', 'tipo_comprobante_factura,tipo_comprobante_venta:s', False, True);
  P('GetFormasPago', 'tipo:s,solo_activas:b', False, True);
  P('SaveFormaPago', 'id:i,nombre!:s,tipo:s,cuenta_codigo!:s,maneja_vencimiento:b,dias_vencimiento:i,activa:b,orden:i,medio_pago_dian:s', True, True);
  P('ToggleFormaPago', 'id!:i,activa:b', True, True);
  P('GetProspectos', 'estado:s,asignado_a:s,busqueda:s', True, True);
  P('SaveProspecto', 'id:i,nombre!:s,empresa:s,cargo:s,email:s,telefono:s,ciudad:s,origen:s,estado:s,asignado_a:s,notas:s', True, True);
  P('ConvertirProspecto', 'id!:i,tipo_id!:s,numero_id!:s', True, True);
  P('GetOportunidades', 'etapa:s,responsable:s', True, True);
  P('SaveOportunidad', 'id:i,nombre!:s,etapa:s,valor_estimado:n,moneda_codigo:s,probabilidad_pct:i,fecha_cierre_estimada:s,responsable_login:s,descripcion:s,motivo_perdida:s,tercero_tipo_id:s,tercero_numero_id:s,prospecto_id:i,cotizacion_id:i', True, True);
  P('GetActividadesCRM', 'responsable:s,estado:s,oportunidad_id:i', True, True);
  P('SaveActividadCRM', 'id:i,tipo:s,asunto!:s,descripcion:s,resultado:s,estado:s,responsable_login:s,tercero_tipo_id:s,tercero_numero_id:s,fecha_programada:s,fecha_realizada:s,duracion_min:i,oportunidad_id:i,prospecto_id:i', True, True);
  P('GetTwilioConfig', '', True, False);
  P('SaveTwilioConfig', 'account_sid:s,sms_from:s,whatsapp_from:s,activo:b,auth_token', True, True);
  P('TestTwilio', 'canal:s,destinatario!:s', True, True);
  P('EnviarSMS', 'celular!:s,mensaje!:s', True, True);
  P('EnviarWhatsApp', 'celular!:s,mensaje!:s', True, True);
  P('GetConversaciones', 'canal,estado,agente_login,page,page_size', True, True);
  P('GetMensajes', 'conversacion_id:i', True, True);
  P('EnviarMensaje', 'conversacion_id!:i,contenido!:s', True, True);
  P('CerrarConversacion', 'conversacion_id!:i', True, True);
  P('AsignarAgenteConv', 'conversacion_id!:i,agente_login!:s', True, True);
  P('GetContacto360', 'tipo_id!:s,numero_id!:s', True, True);
  P('GetCampanas', '', False, True);
  P('SaveCampana', 'nombre:s,canal:s,mensaje!:s,audiencia_tipo:s,filtro_estado:s,filtro_ciudad:s,filtro_es_cliente:b,destinatarios_manual!:a', True, True);
  P('EnviarCampana', 'id!:i', True, True);
  P('GetCampanaDetalle', 'id!:i', True, True);
  P('GetPipeline', '', False, True);
  P('SaveEtapa', 'id:i,pipeline_id:i,nombre!:s,orden:i,color:s,probabilidad_default:i,tipo:s', True, True);
  P('DeleteEtapa', 'id!:i', True, True);
  P('ReorderEtapas', 'pipeline_id:i,ids!:a', True, True);
end;

function ContaParamsDe(const AOp: string): TContaParamSpec;
var
  R: TSpecRaw;
  Partes: TArray<string>;
  i, PColon: Integer;
  S: string;
  D: TContaParamDef;
begin
  Result := Default(TContaParamSpec);
  if GSpecs = nil then
    Build;
  if not GSpecs.TryGetValue(LowerCase(AOp), R) then
    Exit;
  Result.Encontrada := True;
  Result.Completa := R.Completa;
  Result.Recibe := R.Recibe;
  if R.Spec = '' then
    Exit;
  Partes := R.Spec.Split([',']);
  SetLength(Result.Params, Length(Partes));
  for i := 0 to High(Partes) do
  begin
    S := Partes[i];
    D := Default(TContaParamDef);
    PColon := Pos(':', S);
    if PColon > 0 then
    begin
      D.Tipo := S[PColon + 1];
      S := Copy(S, 1, PColon - 1);
    end;
    if S.EndsWith('!') then
    begin
      D.Requerida := True;
      S := Copy(S, 1, Length(S) - 1);
    end;
    D.Name := S;
    Result.Params[i] := D;
  end;
end;

initialization

finalization
  GSpecs.Free;

end.
