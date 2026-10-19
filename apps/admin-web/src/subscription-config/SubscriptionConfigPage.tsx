import { Alert, Button, Checkbox, Form, Input, InputNumber, Modal, Radio, Select, Space, Spin, Switch, Table, Tag, Tooltip, Typography, message } from "antd";
import type { ColumnsType } from "antd/es/table";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRequestId } from "../request-id";
import {
  MAX_DISPLAY_SKUS, PAGE_LABELS, admissionMessage, availableProducts, blankSku, changeProduct, changeTrialProduct, editorFromRecord, emptyCopy,
  moveSku, newEditor, priceDisplayMode, productLabel, productMap, removeSku, subscriptionErrorMessage, toDisplayConfig,
  unlinkTrial, validateEditor,
} from "./model";
import type { Catalog, CatalogProduct, Catalogs, ConfigList, ConfigRecord, CopyFields, Editor, EditorConfig, FieldIssue, PriceDisplayMode, ProductType, SubscriptionRequest } from "./model";
import { SubscriptionMutation } from "./mutation";
import type { MutationFailure, MutationState, PendingOperation } from "./mutation";
import "./SubscriptionConfigPage.css";

const { Text, Title } = Typography;
const emptyCatalogs = (): Catalogs => ({ subscription: { status: "idle", products: [] }, non_consumable: { status: "idle", products: [] } });
type LeaveGuard = () => Promise<boolean>;
type Props = { request: SubscriptionRequest; accountKey: string; registerLeaveGuard: (guard: LeaveGuard | null) => void };

export default function SubscriptionConfigPage({ request, accountKey, registerLeaveGuard }: Props) {
  const [modal, modalContext] = Modal.useModal();
  const coordinator = useMemo(() => new SubscriptionMutation({ request, key: "kando.subscription.pending." + accountKey,
    storage: { getItem: (key) => sessionStorage.getItem(key), setItem: (key, value) => sessionStorage.setItem(key, value), removeItem: (key) => sessionStorage.removeItem(key) },
  }), [request, accountKey]);
  const [mutation, setMutation] = useState<MutationState>(coordinator.state);
  const [editor, setEditor] = useState<Editor | null>(() => coordinator.state.pending?.editor ?? null);
  const baseline = useRef(coordinator.state.pending?.baseline ?? "");
  const [list, setList] = useState<ConfigList>({ items: [], active: [] });
  const [listState, setListState] = useState<"loading" | "loaded" | "error">("loading");
  const [listError, setListError] = useState<string | null>(null);
  const [detail, setDetail] = useState<{ id: string; state: "loading" | "error"; message?: string } | null>(null);
  const [catalogs, setCatalogs] = useState<Catalogs>(emptyCatalogs);
  const [approval, setApproval] = useState<CatalogProduct | null>(null);
  const [approvalEvent, setApprovalEvent] = useState("");
  const [approvalAcknowledged, setApprovalAcknowledged] = useState(false);
  const [validationActive, setValidationActive] = useState(false);
  const [serverIssues, setServerIssues] = useState<FieldIssue[]>([]);
  const [operationError, setOperationError] = useState<MutationFailure | null>(null);
  const [page, setPage] = useState(1);
  const panel = useRef<HTMLElement>(null);
  const listScroll = useRef(0);
  const alive = useRef(true);
  const listLoad = useRef({ version: 0, controller: null as AbortController | null });
  const detailLoad = useRef({ version: 0, controller: null as AbortController | null });
  const catalogLoads = useRef({ subscription: { version: 0, controller: null as AbortController | null }, non_consumable: { version: 0, controller: null as AbortController | null } });
  const handledResult = useRef(0);
  const confirmInFlight = useRef<Promise<boolean> | null>(null);
  const products = useMemo(() => productMap(catalogs), [catalogs]);
  const locked = coordinator.blocked;
  const busy = mutation.phase === "submitting" || mutation.phase === "checking";
  const dirty = !!editor && JSON.stringify(editor.body) !== baseline.current;
  const issues = useMemo(() => [...(editor && validationActive ? validateEditor(editor.body, catalogs, editor.enabled) : []), ...serverIssues], [editor, catalogs, validationActive, serverIssues]);

  const confirm = useCallback((title: string, content: string) => new Promise<boolean>((resolve) => {
    modal.confirm({ title, content, okText: "确认", cancelText: "取消", onOk: () => { resolve(true); }, onCancel: () => { resolve(false); } });
  }), [modal]);

  const loadList = useCallback(async () => {
    const state = listLoad.current; state.controller?.abort(); state.controller = new AbortController();
    const version = ++state.version;
    setListState("loading"); setListError(null);
    try {
      const data = await request<ConfigList>("/subscription-configs", { signal: state.controller.signal });
      if (!alive.current || version !== state.version) return;
      if (!Array.isArray(data?.items) || !Array.isArray(data.active)) throw new Error("配置列表格式异常");
      setList(data); setListState("loaded");
    } catch (error) {
      if (!alive.current || version !== state.version || state.controller.signal.aborted) return;
      setListState("error"); setListError(subscriptionErrorMessage(error));
    }
  }, [request]);

  const loadCatalog = useCallback(async (type: ProductType) => {
    const state = catalogLoads.current[type]; state.controller?.abort(); state.controller = new AbortController();
    const version = ++state.version;
    setCatalogs((current) => ({ ...current, [type]: { ...current[type], status: "loading", error: undefined } }));
    try {
      const data = await request<Catalog>("/subscription-products?type=" + type, { signal: state.controller.signal });
      if (!alive.current || version !== state.version) return;
      if (!Array.isArray(data?.products)) throw new Error("商品目录格式异常");
      setCatalogs((current) => ({ ...current, [type]: { status: "loaded", products: data.products, scope: data.scope, environment: data.environment, can_approve: data.can_approve } }));
    } catch (error) {
      if (!alive.current || version !== state.version || state.controller.signal.aborted) return;
      setCatalogs((current) => ({ ...current, [type]: { ...current[type], status: "error", error: subscriptionErrorMessage(error) } }));
    }
  }, [request]);

  useEffect(() => {
    alive.current = true;
    handledResult.current = 0;
    const unsubscribe = coordinator.subscribe(setMutation);
    void loadList();
    if (coordinator.state.pending) void coordinator.reconcile();
    return () => {
      alive.current = false; unsubscribe(); coordinator.stop();
      for (const state of [listLoad.current, detailLoad.current, ...Object.values(catalogLoads.current)]) { state.version += 1; state.controller?.abort(); }
    };
  }, [coordinator, loadList]);

  useEffect(() => {
    const types = new Set<ProductType>([...list.items.flatMap((item) => item.body.skus), ...(editor?.body.skus ?? [])].map((sku) => sku.product_type));
    for (const type of types) if (catalogs[type].status === "idle") void loadCatalog(type);
  }, [list.items, editor, catalogs, loadCatalog]);

  useEffect(() => {
    const result = mutation.result;
    if (!result || handledResult.current === result.sequence) return;
    handledResult.current = result.sequence;
    if (result.error) {
      setOperationError(result.error);
      setServerIssues(result.error.fields?.map((field) => ({ path: field.path, message: serverFieldMessage(field.message) })) ?? []);
      if (result.operation.editor && !editor) { setEditor(result.operation.editor); baseline.current = result.operation.baseline; }
    } else {
      setOperationError(null); setServerIssues([]); setValidationActive(false); setDetail(null);
      if (result.operation.kind !== "activate" && result.operation.kind !== "admit") { setEditor(null); baseline.current = ""; }
      if (result.operation.kind === "admit") {
        setApproval(null);
        void loadCatalog(result.operation.body.product_type as ProductType);
      }
      message.success(result.operation.kind === "admit" ? "商品已准入，可保存并启用配置" : result.operation.kind === "activate" ? "生效状态已更新" : "配置已保存");
      requestAnimationFrame(() => { if (panel.current) panel.current.scrollTop = listScroll.current; });
    }
    void loadList();
  }, [mutation.result, editor, loadList, loadCatalog]);

  const canLeave = useCallback(async (): Promise<boolean> => {
    if (coordinator.busy) { message.info("正在提交或核对结果，请等待本次操作结束。"); return false; }
    if (coordinator.state.pending) return true;
    if (!dirty) return true;
    if (!confirmInFlight.current) confirmInFlight.current = confirm("放弃未保存的修改？", "离开后将丢弃本次未保存内容，已保存配置保持不变。").finally(() => { confirmInFlight.current = null; });
    return confirmInFlight.current;
  }, [coordinator, dirty, confirm]);
  useEffect(() => { registerLeaveGuard(canLeave); return () => registerLeaveGuard(null); }, [canLeave, registerLeaveGuard]);
  useEffect(() => {
    const warn = (event: BeforeUnloadEvent) => { if (dirty || mutation.pending) { event.preventDefault(); event.returnValue = ""; } };
    window.addEventListener("beforeunload", warn); return () => window.removeEventListener("beforeunload", warn);
  }, [dirty, mutation.pending]);

  const backToList = async () => {
    if (!await canLeave()) return;
    detailLoad.current.version += 1; detailLoad.current.controller?.abort();
    setEditor(null); setDetail(null); setValidationActive(false); setServerIssues([]); baseline.current = "";
    requestAnimationFrame(() => { if (panel.current) panel.current.scrollTop = listScroll.current; });
  };
  const openEditor = async (id: string) => {
    if (locked) return;
    listScroll.current = panel.current?.scrollTop ?? 0;
    const state = detailLoad.current; state.controller?.abort(); state.controller = new AbortController();
    const version = ++state.version;
    setDetail({ id, state: "loading" }); setEditor(null); setServerIssues([]); setOperationError(null); setValidationActive(false);
    try {
      const record = await request<ConfigRecord>("/subscription-configs/" + id, { signal: state.controller.signal });
      if (!alive.current || state.version !== version) return;
      const next = editorFromRecord(record, createRequestId);
      baseline.current = JSON.stringify(next.body); setEditor(next); setDetail(null);
      if (panel.current) panel.current.scrollTop = 0;
    } catch (error) {
      if (alive.current && state.version === version && !state.controller.signal.aborted) setDetail({ id, state: "error", message: subscriptionErrorMessage(error) });
    }
  };
  const updateBody = (transform: (body: EditorConfig) => EditorConfig) => {
    if (locked) return;
    setEditor((current) => current ? { ...current, body: transform(current.body) } : current);
    setServerIssues([]); setOperationError(null);
  };
  const openApproval = (product: CatalogProduct) => {
    setApproval(product); setApprovalEvent(""); setApprovalAcknowledged(false);
  };
  const approveProduct = async () => {
    if (!approval || !approvalAcknowledged || locked) return;
    const catalog = catalogs[approval.product_type];
    if (!catalog.can_approve || !catalog.scope || !/^[A-Za-z][A-Za-z0-9_]{0,99}$/.test(approvalEvent)) return;
    setApproval(null);
    await coordinator.start({ version: 1, kind: "admit", path: "/subscription-products/admit", method: "POST",
      body: { request_id: createRequestId(), product_id: approval.product_id, product_type: approval.product_type,
        expected_scope: catalog.scope, singular_event_name: approvalEvent, acknowledge_legacy_restore_limit: true },
      editor, baseline: baseline.current });
  };
  const updateSku = (index: number, transform: (sku: EditorConfig["skus"][number]) => EditorConfig["skus"][number]) => {
    updateBody((body) => ({ ...body, skus: body.skus.map((sku, i) => i === index ? transform(sku) : sku) }));
  };
  const removeRelation = async (index: number, removeCard = false) => {
    if (!editor || locked) return;
    const sku = editor.body.skus[index];
    const last = editor.body.trial_enabled && !!(sku.trial?.product_id || sku.needs_trial_repair) &&
      !editor.body.skus.some((other) => other.key !== sku.key && other.trial?.product_id);
    if (last && !await confirm("解除最后一组试用关系？", "确认后将同时关闭本组试用切换，已填写的文案会保留。")) return;
    if (!last && removeCard && sku.trial?.product_id && !await confirm("移除 SKU？", "此卡片及其试用关系会从当前编辑副本移除，不影响其他卡片或已有购买。")) return;
    updateBody((body) => removeCard ? removeSku(body, sku.key) : unlinkTrial(body, sku.key));
  };
  const save = () => {
    if (!editor || locked) return;
    setValidationActive(true); setServerIssues([]); setOperationError(null);
    const nextIssues = validateEditor(editor.body, catalogs, editor.enabled);
    if (nextIssues.length) { message.warning("请先修正配置校验错误"); return; }
    const operation: PendingOperation = { version: 1, kind: editor.id ? "save" : "create",
      path: "/subscription-configs" + (editor.id ? "/" + editor.id : ""), method: editor.id ? "PUT" : "POST",
      body: { request_id: createRequestId(), config: toDisplayConfig(editor.body), ...(editor.id ? { expected_revision: editor.revision } : {}) },
      editor: structuredClone(editor), baseline: baseline.current };
    listLoad.current.version += 1; listLoad.current.controller?.abort();
    void coordinator.start(operation);
  };
  const toggle = async (record: ConfigRecord, nextEnabled: boolean) => {
    if (locked || listState !== "loaded") return;
    const pointer = list.active.find((item) => item.page_type === record.page_type);
    if (!pointer) { message.error("无法确认当前生效状态，请刷新列表。"); return; }
    if (nextEnabled && pointer.config_id && pointer.config_id !== record.id) {
      const previous = list.items.find((item) => item.id === pointer.config_id);
      if (!previous) { message.error("生效配置已变化，请刷新列表。"); return; }
      if (!await confirm("替换生效配置？", `将关闭“${previous.body.name}”，并开启“${record.body.name}”。仅影响${PAGE_LABELS[record.page_type]}下次读取。`)) return;
    }
    if (coordinator.blocked) return;
    listLoad.current.version += 1; listLoad.current.controller?.abort();
    void coordinator.start({ version: 1, kind: "activate", method: "PUT", path: "/subscription-configs/active/" + record.page_type,
      body: { request_id: createRequestId(), config_id: nextEnabled ? record.id : null, expected_active_revision: pointer.active_revision,
        ...(nextEnabled ? { expected_config_revision: record.revision } : {}) }, editor: null, baseline: "" });
  };
  const knownUnadmitted = (record: ConfigRecord) => record.body.skus.flatMap((sku) => [sku.product_id,
    ...(record.body.trial_enabled && sku.trial?.product_id ? [sku.trial.product_id] : [])])
    .some((id) => { const product = products.get(id); return product && catalogs[product.product_type].status === "loaded" && !product.admission.admitted; });
  const columns: ColumnsType<ConfigRecord> = [
    { title: "配置名称", dataIndex: ["body", "name"], width: 180 },
    { title: "页面类型", dataIndex: "page_type", width: 120, render: (value) => PAGE_LABELS[value as keyof typeof PAGE_LABELS] },
    { title: "商品信息", width: 250, render: (_, row) => <Space direction="vertical" size={2}>{row.body.skus.map((sku) => <Text code key={sku.product_id}>{sku.product_id}</Text>)}</Space> },
    { title: "试用配置", width: 250, render: (_, row) => <TrialSummary record={row} products={products} known={catalogs.subscription.status === "loaded"} /> },
    { title: "生效状态", width: 125, render: (_, row) => <Space direction="vertical" size={3}><Tooltip title={!row.enabled && knownUnadmitted(row) ? "存在未完成系统准入的商品" : undefined}>
      <Switch aria-label={`${row.body.name}生效状态`} checked={row.enabled} disabled={locked || listState !== "loaded" || (!row.enabled && knownUnadmitted(row))} onChange={(value) => void toggle(row, value)} />
    </Tooltip><Text type="secondary">{row.enabled ? "生效" : "不生效"}</Text></Space> },
    { title: "更新时间", dataIndex: "updated_at", width: 175, render: (value: string) => new Date(value).toLocaleString("zh-CN", { hour12: false }) },
    { title: "操作", width: 75, fixed: "right", render: (_, row) => <Button type="link" disabled={locked} onClick={() => void openEditor(row.id)}>编辑</Button> },
  ];

  return <section ref={panel} className="page-panel subscription-config-page" aria-label="订阅页配置">
    {modalContext}
    <Modal title="审核商品准入" open={!!approval} onCancel={() => { if (!locked) setApproval(null); }}
      confirmLoading={busy} closable={!locked} maskClosable={!locked} cancelButtonProps={{ disabled: locked }}
      okText="确认当前环境准入" onOk={() => void approveProduct()}
      okButtonProps={{ disabled: locked || !approvalAcknowledged || !/^[A-Za-z][A-Za-z0-9_]{0,99}$/.test(approvalEvent) }}>
      {approval && <Space direction="vertical" style={{ width: "100%" }}>
        <Alert type={catalogs[approval.product_type].environment === "production" ? "error" : "info"} showIcon
          message={catalogs[approval.product_type].environment === "production" ? "目标：生产环境 prod" : "目标：开发环境 dev"}
          description={catalogs[approval.product_type].scope} />
        <Text strong>{approval.product_id}</Text>
        <Text>类型：{approval.product_type === "subscription" ? "自动续期订阅" : "永久权益"}；权益：Premium；Apple 状态：{approval.state}</Text>
        <Text>审批会注册服务端购买与展示准入，页面仍需单独启用。App 需安装支持动态商品注册表的版本；Apple 可售状态和真实购买仍需测试。</Text>
        <Form.Item label="当前环境的 Singular 收入事件名" required help="由数据负责人确认；只允许英文字母开头及字母、数字、下划线。">
          <Input aria-label="准入收入事件名" value={approvalEvent} maxLength={100} disabled={locked} onChange={(e) => setApprovalEvent(e.target.value)} />
        </Form.Item>
        <Checkbox checked={approvalAcknowledged} disabled={locked} onChange={(e) => setApprovalAcknowledged(e.target.checked)}>
          已核对当前环境、Premium 权益及收入事件，并确认新 SKU 在 1.0.4／1.0.5 中无法恢复的支持边界。
        </Checkbox>
      </Space>}
    </Modal>
    {mutation.phase === "submitting" && <Alert type="info" showIcon message="正在提交，请勿重复操作" />}
    {mutation.phase === "checking" && <Alert type="info" showIcon message="正在核对原操作结果，请稍候" description="暂不判断成功或失败，相关写入已锁定。" />}
    {mutation.warning && <Alert type="warning" showIcon message={mutation.warning} />}
    {mutation.phase === "unknown" && mutation.pending && <Space wrap className="subscription-recovery-actions">
      <Button onClick={() => void coordinator.reconcile()}>核对原操作</Button>
      <Button onClick={() => void coordinator.reconcile(true)}>核对并重试原操作</Button>
      {mutation.pending.editor && !editor && <Button onClick={() => { setEditor(mutation.pending!.editor); baseline.current = mutation.pending!.baseline; }}>查看保留的输入</Button>}
      <Text type="secondary">仅使用原请求重试；结果确认前不能提交另一份配置。</Text>
    </Space>}
    {operationError && <Alert type="error" showIcon message={subscriptionErrorMessage(operationError)} action={editor?.id && ["CONFIG_CONFLICT", "ACTIVE_PAGE_TYPE_IMMUTABLE"].includes(operationError.code)
      ? <Button onClick={async () => { if (await confirm("重新载入配置？", "这会丢弃当前编辑内容，改为服务端最新内容。")) void openEditor(editor.id!); }}>载入最新配置</Button> : undefined} />}

    {detail ? <div className="subscription-detail-state">
      <Button onClick={() => void backToList()}>返回列表</Button>
      {detail.state === "loading" ? <Spin tip="正在读取配置详情"><div className="subscription-detail-placeholder" /></Spin> : <Alert type="error" showIcon message={detail.message} action={<Button onClick={() => void openEditor(detail.id)}>重试</Button>} />}
    </div> : editor ? <>
      <div className="subscription-editor-toolbar">
        <div><Button type="link" disabled={busy} onClick={() => void backToList()}>‹ 返回配置列表</Button><Title level={4}>{editor.id ? "编辑配置" : "新增配置"}</Title><Text type="secondary">保存更新内容，生效状态在列表单独设置。</Text></div>
        <Space><Button disabled={busy} onClick={() => void backToList()}>取消</Button><Button className="cyan-button" disabled={locked} loading={busy} onClick={save}>保存</Button></Space>
      </div>
      <Form layout="vertical" className="subscription-config-form" disabled={locked}>
        <section className="subscription-form-section"><Title level={5}>基础信息</Title><div className="subscription-field-grid">
          <Field label="配置名称" path="name" issues={issues} required><Input aria-label="配置名称" value={editor.body.name} maxLength={100} showCount onChange={(event) => updateBody((body) => ({ ...body, name: event.target.value }))} /></Field>
          <Field label="页面类型" path="page_type" issues={issues} required><Select aria-label="页面类型" placeholder="请选择" value={editor.body.page_type || undefined} disabled={locked || editor.enabled} options={Object.entries(PAGE_LABELS).map(([value, label]) => ({ value, label }))} onChange={(value) => updateBody((body) => ({ ...body, page_type: value }))} /></Field>
        </div>{editor.enabled && <Text type="secondary">当前配置已生效，保存后用于后续读取；修改页面类型前须先在列表关闭。</Text>}</section>
        <section className="subscription-form-section"><Title level={5}>试用切换设置</Title>
          <Field label="启用试用切换" path="trial_enabled" issues={issues}><Checkbox checked={editor.body.trial_enabled} onChange={(event) => updateBody((body) => ({ ...body, trial_enabled: event.target.checked }))}>为普通订阅配置关联试用</Checkbox></Field>
          {editor.body.trial_enabled && <Field label="试用开关文案" path="trial_toggle_text" issues={issues} required><Input aria-label="试用开关文案" value={editor.body.trial_toggle_text} maxLength={100} showCount onChange={(event) => updateBody((body) => ({ ...body, trial_toggle_text: event.target.value }))} /></Field>}
          <Text type="secondary">客户端开关默认关闭。关系须同组、同周期、同等级；独立试用商品无需关联。实际资格由 Apple 确认，无资格或未知时不展示免费承诺。</Text>
        </section>
        <section className="subscription-form-section"><div className="panel-heading"><Title level={5}>页面展示 SKU</Title><Button disabled={locked || editor.body.skus.length >= MAX_DISPLAY_SKUS} onClick={() => updateBody((body) => body.skus.length >= MAX_DISPLAY_SKUS ? body : { ...body, skus: [...body.skus, blankSku(createRequestId())] })}>＋ 增加 SKU</Button></div>
          <Field label="默认项与商品数量" path="skus" issues={issues}><Text type="secondary">页面展示 SKU 最少 1 个，最多 {MAX_DISPLAY_SKUS} 个，必须且只能选择一个默认项；关联试用 SKU 不占名额，独立展示的试用 SKU 计入数量。</Text></Field>
          {editor.body.skus.map((sku, index) => {
            const path = "skus." + index + ".";
            const product = products.get(sku.product_id);
            const catalog = catalogs[sku.product_type];
            const displayOptions = availableProducts(editor.body, index, catalog.products);
            const trialOptions = availableProducts(editor.body, index, catalogs.subscription.products, true);
            const trial = sku.trial ?? { ...emptyCopy(), product_id: "" };
            const hasRelation = !!sku.trial?.product_id || sku.needs_trial_repair;
            return <article className="subscription-sku-card" key={sku.key} aria-label={`页面展示 SKU ${index + 1}`}>
              <header className="subscription-sku-header"><strong>页面展示 SKU {index + 1}</strong><Space size={4}>
                <Button aria-label={`上移 SKU ${index + 1}`} disabled={locked || index === 0} onClick={() => updateBody((body) => moveSku(body, index, -1))}>↑</Button>
                <Button aria-label={`下移 SKU ${index + 1}`} disabled={locked || index === editor.body.skus.length - 1} onClick={() => updateBody((body) => moveSku(body, index, 1))}>↓</Button>
                <Button danger disabled={locked} onClick={() => void removeRelation(index, true)}>移除</Button>
              </Space></header>
              <Field label="商品类型" path={path + "product_type"} issues={issues} required><Radio.Group value={sku.product_type} onChange={(event) => updateSku(index, (item) => changeProduct(item, "", products, event.target.value))} options={[{ value: "subscription", label: "订阅" }, { value: "non_consumable", label: "一次性购买" }]} /></Field>
              <Field label="Product ID" path={path + "product_id"} issues={issues} required><Select aria-label={`SKU ${index + 1} Product ID`} className="subscription-product-select" value={sku.product_id || undefined} placeholder="请选择商品" disabled={locked || catalog.status !== "loaded"} options={productOptions(displayOptions, sku.product_id, products)} onChange={(value) => updateSku(index, (item) => changeProduct(item, value, products))} /></Field>
              <CatalogFeedback state={catalog} type={sku.product_type} disabled={locked} reload={() => void loadCatalog(sku.product_type)} />
              {product && !product.admission.admitted && <Alert type="warning" showIcon message="该商品尚未完成系统准入" description={admissionMessage(product.admission.reasons) + "。可准备不生效配置，不能启用。"} />}
              {product && catalog.can_approve && <Button disabled={locked || catalog.status !== "loaded"} onClick={() => openApproval(product)}>审核商品准入</Button>}
              <div className="subscription-field-grid">
                <Field label="价格展示方式" path={path + "price_mode"} issues={issues}><Select aria-label={`SKU ${index + 1} 价格展示方式`} value={priceDisplayMode(sku)} options={[{ value: "actual", label: "实际周期价格" }, { value: "weekly", label: "实际周期价格 + 周均参考价", disabled: sku.product_type === "non_consumable" || !!product && !["ONE_WEEK", "ONE_MONTH", "THREE_MONTHS", "ONE_YEAR"].includes(product.period ?? "") }, { value: "hidden", label: "不展示" }]} onChange={(value: PriceDisplayMode) => updateSku(index, (item) => ({ ...item, price_mode: value === "hidden" ? item.price_mode : value, hide_price: value === "hidden" }))} /></Field>
                <Field label="默认选中" path={path + "is_default"} issues={issues}><Checkbox checked={sku.is_default} onChange={(event) => updateBody((body) => ({ ...body, skus: body.skus.map((item) => ({ ...item, is_default: item.key === sku.key ? event.target.checked : event.target.checked ? false : item.is_default })) }))}>将此卡片设为默认</Checkbox></Field>
              </div>
              <MarketingFields value={sku} prefix={path} issues={issues} onChange={(value) => updateSku(index, (item) => ({ ...item, ...value }))} />
              {editor.body.trial_enabled && sku.product_type === "non_consumable" && sku.needs_trial_repair && <div id={"subscription-field-" + path + "trial.product_id"}><Alert type="warning" showIcon message="商品类型已变化，请明确解除原试用关系后保存。" action={<Button disabled={locked} onClick={() => void removeRelation(index)}>解除原关系</Button>} /></div>}
              {!editor.body.trial_enabled && hasRelation && <div className="subscription-trial-section"><Tag>已保留但未启用</Tag><Text code>{trial.product_id || "原关系待调整"}</Text><Button disabled={locked} onClick={() => void removeRelation(index)}>解除试用关联</Button></div>}
              {editor.body.trial_enabled && sku.product_type === "subscription" && (!product?.has_free_trial || hasRelation) && <div className="subscription-trial-section"><Title level={5}>关联试用 SKU</Title>
                <Field label="试用 Product ID" path={path + "trial.product_id"} issues={issues}><Select aria-label={`SKU ${index + 1} 试用 Product ID`} allowClear value={trial.product_id || undefined} placeholder="默认不关联" disabled={locked || catalogs.subscription.status !== "loaded" || !product || product.has_free_trial}
                  options={productOptions(trialOptions, trial.product_id, products)} onChange={(value) => { if (!value) void removeRelation(index); else updateSku(index, (item) => ({ ...item, needs_trial_repair: false, trial: changeTrialProduct(trial, value, products) })); }} /></Field>
                {trial.product_id && <Button disabled={locked} onClick={() => void removeRelation(index)}>解除试用关联</Button>}
                {sku.needs_trial_repair && <Alert type="warning" message="商品已变化，请重新关联或明确解除原关系。" action={<Button disabled={locked} onClick={() => void removeRelation(index)}>解除原关系</Button>} />}
                {catalogs.subscription.status === "loaded" && !trialOptions.length && !trial.product_id && <Text type="secondary">没有同周期、同等级且未占用的免费试用商品。</Text>}
                {trial.product_id && <><Text type="secondary">开启试用时只替换当前卡片。试用按钮为空时回退组级文案，不继承基础按钮。</Text>
                  <Field label="价格展示方式" path={path + "trial.price_mode"} issues={issues}><Select aria-label={`SKU ${index + 1} 试用价格展示方式`} value={priceDisplayMode(sku, trial)} options={[{ value: "actual", label: "实际周期价格" }, { value: "weekly", label: "实际周期价格 + 周均参考价", disabled: !!products.get(trial.product_id) && !["ONE_WEEK", "ONE_MONTH", "THREE_MONTHS", "ONE_YEAR"].includes(products.get(trial.product_id)?.period ?? "") }, { value: "hidden", label: "不展示" }]} onChange={(value: PriceDisplayMode) => updateSku(index, (item) => ({ ...item, trial: { ...trial, ...(value === "hidden" ? {} : { price_mode: value }), hide_price: value === "hidden" } }))} /></Field>
                  <MarketingFields value={trial} prefix={path + "trial."} issues={issues} trial onChange={(value) => updateSku(index, (item) => ({ ...item, trial: { ...trial, ...value } }))} />
                  {products.get(trial.product_id) && catalogs.subscription.can_approve && <Button disabled={locked} onClick={() => openApproval(products.get(trial.product_id)!)}>审核试用商品准入</Button>}
                  {products.get(trial.product_id)?.admission.admitted === false && <Alert type="warning" showIcon message="试用目标尚未完成系统准入，不能作为生效购买商品。" />}</>}
              </div>}
            </article>;
          })}
        </section>
        <section className="subscription-form-section"><Title level={5}>页面统一配置</Title><div className="subscription-field-grid">
          <Field label="组级订阅按钮兜底文案" path="cta" issues={issues}><Input aria-label="组级订阅按钮兜底文案" value={editor.body.cta} maxLength={100} showCount onChange={(event) => updateBody((body) => ({ ...body, cta: event.target.value }))} /></Field>
          <Field label="关闭按钮延迟（秒）" path="close_delay_seconds" issues={issues} required><InputNumber aria-label="关闭按钮延迟（秒）" value={editor.body.close_delay_seconds} min={0} step={1} onChange={(value) => updateBody((body) => ({ ...body, close_delay_seconds: value }))} /></Field>
        </div><Text type="secondary">按钮仅支持纯文本：当前 SKU → 组级 → SUBSCRIBE。0 秒立即显示关闭入口，重试和切换 SKU 不重新计时。</Text></section>
        {!!issues.length && <Alert type="error" showIcon message="请修正以下内容" description={<ul className="subscription-validation-list">{issues.map((issue, index) => <li key={issue.path + index}><a onClick={() => document.getElementById("subscription-field-" + issue.path)?.scrollIntoView({ block: "center" })}>{issue.message}</a></li>)}</ul>} />}
      </Form>
    </> : <>
      <div className="panel-heading"><div><Title level={4}>订阅页配置</Title><Text type="secondary">订阅页与订阅大弹窗各自最多一组生效，也可全部关闭。</Text></div><Space><Button disabled={locked} loading={listState === "loading"} onClick={() => void loadList()}>刷新</Button><Button className="cyan-button" disabled={locked || listState !== "loaded"} onClick={() => { listScroll.current = panel.current?.scrollTop ?? 0; const next = newEditor(createRequestId()); baseline.current = JSON.stringify(next.body); setEditor(next); setValidationActive(false); setServerIssues([]); setOperationError(null); if (panel.current) panel.current.scrollTop = 0; }}>新增配置</Button></Space></div>
      {listError && <Alert type="error" showIcon message={listError} description="保留最后确认的列表，刷新成功前不可切换生效状态。" action={<Button disabled={locked} onClick={() => void loadList()}>重试</Button>} />}
      <Table<ConfigRecord> rowKey="id" columns={columns} dataSource={list.items} loading={listState === "loading"} scroll={{ x: 1175 }} pagination={{ current: page, pageSize: 8, onChange: setPage, showSizeChanger: false }} locale={{ emptyText: listState === "error" ? "配置读取失败，请重试" : "暂无配置，点击新增配置开始" }} />
      {Object.entries(catalogs).filter(([, catalog]) => catalog.status === "error").map(([type, catalog]) => <CatalogFeedback key={type} state={catalog} type={type as ProductType} disabled={locked} reload={() => void loadCatalog(type as ProductType)} />)}
    </>}
  </section>;
}

function Field({ label, path, issues, required, children }: { label: string; path: string; issues: FieldIssue[]; required?: boolean; children: React.ReactNode }) {
  const errors = issues.filter((issue) => issue.path === path).map((issue) => issue.message);
  return <div id={"subscription-field-" + path}><Form.Item label={label} required={required} validateStatus={errors.length ? "error" : undefined} help={errors.length ? errors.join("；") : undefined}>{children}</Form.Item></div>;
}
function MarketingFields({ value, prefix, issues, onChange, trial = false }: { value: CopyFields; prefix: string; issues: FieldIssue[]; trial?: boolean; onChange: (value: Partial<CopyFields>) => void }) {
  return <>
    {([["name", trial ? "试用商品展示名称" : "商品展示名称", 100], ["subtitle", "名称下方副文案", 300], ["badge", "右上角角标", 100], ["price_note", "价格下方说明", 200], ["cta", "订阅按钮文案", 100]] as const).map(([key, label, max]) =>
      <Field key={key} label={label} path={prefix + key} issues={issues} required={key === "name"}><Input aria-label={prefix + label} value={value[key]} maxLength={max} showCount onChange={(event) => onChange({ [key]: event.target.value })} /></Field>)}
    <Field label="购买按钮上方说明方式" path={prefix + "billing_note_mode"} issues={issues}><Select aria-label={prefix + "说明方式"} value={value.billing_note_mode} options={[{ value: "custom", label: "自定义文本" }, { value: "auto", label: "自动商品说明" }]} onChange={(mode) => onChange({ billing_note_mode: mode })} /></Field>
    {value.billing_note_mode === "custom" ? <Field label="自定义按钮上方说明" path={prefix + "billing_note"} issues={issues}><Input.TextArea aria-label={prefix + "自定义说明"} value={value.billing_note} maxLength={500} showCount autoSize={{ minRows: 2, maxRows: 6 }} onChange={(event) => onChange({ billing_note: event.target.value })} /></Field>
      : <Alert type="info" showIcon message="按实际商品和资格生成说明" description="自动方式在购买按钮上方显示当前商品的真实金额与周期；免费期限只有资格确认后才展示。" />}
    <Text type="secondary">按钮内不支持变量；自定义说明可用 {"{price}"} 表示真实周期价格。自定义文本留空时，按钮上方不显示说明；试用资格未知或无资格时显示中性标准价格说明。</Text>
  </>;
}
function CatalogFeedback({ state, type, disabled, reload }: { state: Catalogs[ProductType]; type: ProductType; disabled: boolean; reload: () => void }) {
  const label = type === "subscription" ? "订阅商品" : "一次性购买商品";
  return <div className="subscription-catalog-status">
    {state.status === "loading" || state.status === "idle" ? <Space><Spin size="small" /><Text type="secondary">正在读取{label}</Text></Space> : state.status === "error" ? <Alert type="error" showIcon message={label + "读取失败"} description={state.error} action={<Button size="small" disabled={disabled} onClick={reload}>重试读取</Button>} />
      : <Space wrap><Text type="secondary">{state.products.length ? label + "已读取" : "当前范围没有可配置的" + label}</Text><Button size="small" disabled={disabled} onClick={reload}>刷新商品</Button></Space>}
  </div>;
}
function productOptions(products: CatalogProduct[], selected: string, all: Map<string, CatalogProduct>) {
  const options = products.map((product) => ({ value: product.product_id, label: productLabel(product), disabled: false }));
  if (selected && !options.some((option) => option.value === selected)) options.unshift({ value: selected, label: all.get(selected) ? productLabel(all.get(selected)!) + " · 当前不可选，请核对" : selected + " · 已保存，待商品信息恢复", disabled: true });
  return options;
}
function TrialSummary({ record, products, known }: { record: ConfigRecord; products: Map<string, CatalogProduct>; known: boolean }) {
  const relations = record.body.skus.filter((sku) => sku.trial?.product_id);
  const independent = record.body.skus.filter((sku) => products.get(sku.product_id)?.has_free_trial).length;
  return <Space direction="vertical" size={2}>
    {!record.body.trial_enabled && <Text type="secondary">试用切换未启用</Text>}
    {relations.map((sku) => <Text key={sku.product_id} type={record.body.trial_enabled ? undefined : "secondary"}>{sku.product_id} → {sku.trial!.product_id}{!record.body.trial_enabled ? "（未使用）" : ""}</Text>)}
    {known ? independent > 0 && <Tag color="cyan">含 {independent} 个独立试用商品</Tag> : <Text type="secondary">独立试用信息待商品读取确认</Text>}
  </Space>;
}
function serverFieldMessage(value: string): string {
  const messages: Record<string, string> = {
    "Product is not in the configured Apple scope or type.": "商品不在当前 App 的指定范围，或类型不匹配。",
    "Weekly reference price is not defined for this period.": "该周期不支持折算周均参考价。",
    "Trial requires a non-trial source and free-trial target in the same group, period and level.": "试用关系不满足同组、同周期、同等级及免费试用条件。",
    "Display and trial Product IDs must be unique in this configuration.": "本组展示商品与试用目标不能重复。",
    "At most 3 display SKUs are allowed.": `页面展示 SKU 最多只能配置 ${MAX_DISPLAY_SKUS} 个`,
    "Button text must be plain text without braces.": "按钮仅支持纯文本，不允许变量或花括号。",
  };
  return messages[value] ?? "服务端校验：" + value;
}
