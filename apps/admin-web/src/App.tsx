import {
  Alert,
  Badge,
  Button,
  DatePicker,
  Drawer,
  Form,
  Input,
  Layout,
  Menu,
  Modal,
  Pagination,
  Select,
  Segmented,
  Space,
  Switch,
  Table,
  Tag,
  Typography,
  message,
} from "antd";
import type { ColumnsType } from "antd/es/table";
import { useEffect, useMemo, useState } from "react";
import "./App.css";
import { resolveAdminApiBase } from "./api-base";

type AdminRole = "super_admin" | "operator";
type MenuKey = "installations" | "users" | "feedbacks" | "scans" | "permissions" | "app-versions";
type FeedbackStatus = "pending" | "processed" | "ignored";
type PermissionStatus = "active" | "disabled";
type AppVersionStatus = "enabled" | "disabled";

type AdminSession = {
  adminId: string;
  email: string;
  role: AdminRole;
  accessToken: string;
  refreshToken: string;
};

type ApiSuccess<T> = { success: true; data: T };
type ApiFailure = { success: false; error: { code: string; message: string } };
type ApiResponse<T> = ApiSuccess<T> | ApiFailure;
type AdminRequestInit = Omit<RequestInit, "body"> & {
  body?: unknown;
  token?: string;
};

type InstallationAnalytics = {
  summary: { total_installations: number; countries: number; platforms: number };
  trend: Array<{ date: string; total: number }>;
  rows: InstallationRow[];
};

type InstallationRow = {
  date: string;
  country: string;
  platform: string;
  environment: string;
  installs: number;
};

type UserItem = {
  account_type: "user" | "anonymous";
  id: string;
  email: string | null;
  device_id: string | null;
  created_at: string;
  status: string;
  platform: string;
  identity: "anonymous" | "email" | "google" | "apple";
};

type UserListResponse = { items: UserItem[]; total: number; page: number; page_size: number };
type UserFilters = { q: string; platform?: string; identity?: string; date_from: string; date_to: string };

type FeedbackTicket = {
  id: string;
  email: string;
  message: string;
  status: FeedbackStatus;
  created_at: string;
  issue_type: string;
  module: string;
  uid: string;
  platform: string;
  app_version: string;
  device_model: string;
  os_version: string;
};

type ScanListItem = {
  scan_id: string;
  image_url: string;
  uid: string;
  platform: string;
  app_version: string;
  scan_time: string;
  recognition_status: string;
  user_confirmation_status: string;
  modified_result: boolean;
};

type ScanDetail = ScanListItem & {
  device_model: string;
  os_version: string;
  system_result: Record<string, unknown>;
  user_result: Record<string, unknown>;
  candidates: Array<Record<string, unknown>>;
};

type ScanListResponse = {
  items: ScanListItem[];
  page: number;
  page_size: number;
  total: number;
};

type PermissionItem = {
  id: string;
  email: string;
  role: AdminRole;
  permission_status: PermissionStatus;
  created_at: string;
  updated_at: string;
};

type AppVersionItem = {
  platform: "iOS" | "Google";
  min_supported_version: string;
  recommended_version: string;
  force_update: boolean;
  store_url: string;
  recommended_update_message: string;
  forced_update_message: string;
  status: AppVersionStatus;
  updated_at: string;
};

const { Sider, Content } = Layout;
const { Title, Text } = Typography;
const { TextArea } = Input;
const API_BASE = resolveAdminApiBase({
  DEV: import.meta.env.DEV,
  VITE_API_BASE_URL: import.meta.env.VITE_API_BASE_URL,
});
const SESSION_STORAGE_KEY = "kando_admin_session";
const SESSION_EXPIRED_EVENT = "kando-admin-session-expired";
const PERIOD_OPTIONS = ["1d", "7d", "15d", "1m", "3m"];

const menuGroups: Array<{ title: string; items: Array<{ key: MenuKey; label: string }> }> = [
  { title: "数据统计", items: [{ key: "installations", label: "安装统计" }] },
  {
    title: "用户管理",
    items: [
      { key: "users", label: "用户列表" },
      { key: "feedbacks", label: "用户反馈" },
      { key: "permissions", label: "权限管理" },
    ],
  },
  { title: "卡牌管理", items: [{ key: "scans", label: "扫描记录管理" }] },
  { title: "App 版本管理", items: [{ key: "app-versions", label: "版本管理" }] },
];

const pageMeta: Record<MenuKey, { title: string; description: string }> = {
  installations: { title: "安装分析", description: "查看各国家与平台安装趋势及明细数据。" },
  users: { title: "用户列表", description: "查看 App 用户的基础信息、登录身份和首次安装时间。" },
  feedbacks: { title: "用户反馈", description: "查看用户提交的反馈内容，并标记处理状态。" },
  scans: { title: "扫描记录管理", description: "查看用户扫描图片、系统识别结果和用户最终确认结果。" },
  permissions: { title: "权限管理", description: "管理允许访问后台的邮箱账号。" },
  "app-versions": { title: "版本管理", description: "管理 iOS 与 Google 端最低支持版本和更新提示。" },
};

export default function App() {
  const [session, setSession] = useState<AdminSession | null>(() => readStoredSession());
  const [authView, setAuthView] = useState<"login" | "password" | "denied">("login");

  useEffect(() => {
    if (session) {
      window.localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
    } else {
      window.localStorage.removeItem(SESSION_STORAGE_KEY);
    }
  }, [session]);

  useEffect(() => {
    const handleSessionExpired = () => {
      setAuthView("login");
      setSession(null);
    };
    window.addEventListener(SESSION_EXPIRED_EVENT, handleSessionExpired);
    return () => window.removeEventListener(SESSION_EXPIRED_EVENT, handleSessionExpired);
  }, []);

  if (!session) {
    if (authView === "password") return <PasswordSetupView onBack={() => setAuthView("login")} />;
    if (authView === "denied") return <AccessDeniedView onBack={() => setAuthView("login")} />;
    return <LoginView onLogin={setSession} onPassword={() => setAuthView("password")} onDenied={() => setAuthView("denied")} />;
  }

  return <AdminShell session={session} onLogout={() => setSession(null)} />;
}

function LoginView({
  onLogin,
  onPassword,
  onDenied,
}: {
  onLogin: (session: AdminSession) => void;
  onPassword: () => void;
  onDenied: () => void;
}) {
  const [submitting, setSubmitting] = useState(false);

  async function handleFinish(values: { email: string; password: string }) {
    setSubmitting(true);
    try {
      const body = await adminRequest<{
        admin_id: string;
        email: string;
        role: AdminRole;
        access_token: string;
        refresh_token: string;
      }>("/auth/login", { method: "POST", body: values });
      onLogin({
        adminId: body.admin_id,
        email: body.email,
        role: body.role,
        accessToken: body.access_token,
        refreshToken: body.refresh_token,
      });
    } catch (error) {
      if (error instanceof AdminApiError && error.code === "FORBIDDEN") onDenied();
      message.error(errorMessage(error));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="auth-page">
      <section className="login-card">
        <div className="brand-lockup">
          <span className="brand-mark">◆</span>
          <div>
            <Title level={3}>TCG Admin</Title>
            <Text>BACKEND PORTAL</Text>
          </div>
        </div>
        <Title level={4}>登录后台</Title>
        <Text className="auth-subtitle">请输入已授权的邮箱账号和密码。</Text>
        <Form layout="vertical" onFinish={handleFinish} requiredMark={false}>
          <Form.Item name="email" label="邮箱账号" rules={[{ required: true, type: "email", message: "请输入正确的邮箱格式" }]}>
            <Input size="large" placeholder="请输入邮箱账号" />
          </Form.Item>
          <Form.Item name="password" label="密码" rules={[{ required: true, message: "请输入密码" }]}>
            <Input.Password size="large" placeholder="请输入密码" />
          </Form.Item>
          <div className="login-link-row">
            <Button type="link" onClick={onPassword}>
              忘记密码?
            </Button>
            <Button type="link" onClick={onPassword}>
              设置密码
            </Button>
          </div>
          <Button className="cyan-button" htmlType="submit" block loading={submitting}>
            登录
          </Button>
        </Form>
        <div className="auth-footer">只有已授权的邮箱账号可以访问后台</div>
      </section>
      <div className="portal-watermark">PORTAL</div>
    </main>
  );
}

function PasswordSetupView({ onBack }: { onBack: () => void }) {
  const [form] = Form.useForm();

  function handleFinish(values: { password: string; confirm: string }) {
    if (values.password !== values.confirm) {
      message.error("两次输入的密码不一致");
      return;
    }
    form.resetFields();
    message.info("请联系超级管理员完成密码开通");
  }

  return (
    <main className="password-page">
      <section className="security-panel">
        <Text className="eyebrow">SECURITY CENTER</Text>
        <Title level={2}>TCG Admin Backend Portal</Title>
        <Text>后台账号由超级管理员授权后生效。</Text>
      </section>
      <section className="password-card">
        <Title level={4}>设置密码</Title>
        <Form form={form} layout="vertical" onFinish={handleFinish} requiredMark={false}>
          <Form.Item name="email" label="邮箱账号" rules={[{ required: true, type: "email" }]}>
            <Input size="large" placeholder="请输入邮箱账号" />
          </Form.Item>
          <Form.Item name="password" label="新密码" rules={[{ required: true }]}>
            <Input.Password size="large" placeholder="请输入新密码" />
          </Form.Item>
          <Form.Item name="confirm" label="确认密码" rules={[{ required: true }]}>
            <Input.Password size="large" placeholder="请再次输入新密码" />
          </Form.Item>
          <Space>
            <Button className="cyan-button" htmlType="submit">
              保存密码
            </Button>
            <Button onClick={onBack}>返回登录</Button>
          </Space>
        </Form>
      </section>
    </main>
  );
}

function AccessDeniedView({ onBack }: { onBack: () => void }) {
  return (
    <main className="denied-page">
      <section className="denied-card">
        <div className="denied-icon">!</div>
        <Title level={3}>访问权限受限</Title>
        <Text>当前账号没有后台访问权限，请联系管理员开通权限。</Text>
        <Space>
          <Button className="cyan-button" onClick={onBack}>
            退出登录
          </Button>
          <Button onClick={onBack}>
            重试登录
          </Button>
        </Space>
        <div className="denied-footer">© TCG ADMIN BACKEND PORTAL</div>
      </section>
      <Button className="support-button">联系技术支持</Button>
    </main>
  );
}

function AdminShell({ session, onLogout }: { session: AdminSession; onLogout: () => void }) {
  const [selected, setSelected] = useState<MenuKey>("installations");
  const selectedMeta = pageMeta[selected];

  return (
    <Layout className="admin-layout">
      <Sider width={186} className="admin-sider">
        <div className="sidebar-brand">
          <strong>TCG Admin</strong>
          <span>Backend Portal</span>
        </div>
        <Menu
          mode="inline"
          selectedKeys={[selected]}
          onClick={(item) => setSelected(item.key as MenuKey)}
          items={menuGroups.map((group) => ({
            key: group.title,
            label: group.title,
            children: group.items,
          }))}
        />
        <div className="sidebar-account">
          <span className="avatar">{session.email.slice(0, 2).toUpperCase()}</span>
          <div>
            <strong>{session.email}</strong>
            <span>{session.role === "super_admin" ? "超级管理员" : "运营管理员"}</span>
          </div>
          <Button type="link" danger onClick={onLogout}>
            Logout
          </Button>
        </div>
      </Sider>
      <Layout>
        <Content className="admin-content">
          <div className="page-title-row">
            <div className="page-title-copy">
              <Title level={3}>{selectedMeta.title}</Title>
              <Text>{selectedMeta.description}</Text>
            </div>
            <Text>{new Date().toLocaleDateString()}</Text>
          </div>
          {selected === "installations" && <InstallationsPage session={session} />}
          {selected === "users" && <UsersPage session={session} />}
          {selected === "feedbacks" && <FeedbackPage session={session} />}
          {selected === "scans" && <ScansPage session={session} />}
          {selected === "permissions" && <PermissionsPage session={session} />}
          {selected === "app-versions" && <AppVersionsPage session={session} />}
        </Content>
      </Layout>
    </Layout>
  );
}

function InstallationsPage({ session }: { session: AdminSession }) {
  const [period, setPeriod] = useState<string>("7d");
  const { data, loading, reload, error } = useAdminData<InstallationAnalytics>("/analytics/installations?page_size=100", session);
  const rows = data?.rows ?? [];
  const trend = data?.trend ?? [];
  const columns: ColumnsType<InstallationRow> = [
    { title: "日期", dataIndex: "date" },
    { title: "国家", dataIndex: "country" },
    { title: "平台", dataIndex: "platform" },
    { title: "环境", dataIndex: "environment" },
    { title: "安装量", dataIndex: "installs" },
  ];

  return (
    <PagePanel error={error} onRefresh={reload}>
      <FilterBar>
        <DatePicker.RangePicker />
        <Select mode="multiple" placeholder="国家" className="filter-control" options={countryOptions} />
        <Select placeholder="环境" className="filter-control" options={environmentOptions} />
        <Button className="cyan-button">搜索</Button>
        <Button>重置</Button>
      </FilterBar>
      <div className="stats-row">
        <Metric label="安装总量" value={data?.summary.total_installations ?? 0} />
        <Metric label="国家数" value={data?.summary.countries ?? 0} />
        <Metric label="平台数" value={data?.summary.platforms ?? 0} />
      </div>
      <section className="chart-panel">
        <div className="panel-heading">
          <Title level={4}>安装趋势</Title>
          <Segmented value={period} onChange={(value) => setPeriod(String(value))} options={PERIOD_OPTIONS} />
        </div>
        <LineChart data={trend} />
      </section>
      <DataPanel title="安装数据" count={rows.length}>
        <Table rowKey={(row) => `${row.date}-${row.country}-${row.platform}`} columns={columns} dataSource={rows} loading={loading} pagination={{ pageSize: 8 }} />
      </DataPanel>
    </PagePanel>
  );
}

function UsersPage({ session }: { session: AdminSession }) {
  const [page, setPage] = useState(1);
  const [dateRangeKey, setDateRangeKey] = useState(0);
  const [draft, setDraft] = useState<UserFilters>({ q: "", date_from: "", date_to: "" });
  const [filters, setFilters] = useState<UserFilters>(draft);
  const path = useMemo(() => {
    const params = new URLSearchParams({ page: String(page), page_size: "8" });
    Object.entries(filters).forEach(([key, value]) => value && params.set(key, value));
    return `/users?${params.toString()}`;
  }, [filters, page]);
  const { data, loading, reload, error } = useAdminData<UserListResponse>(path, session);
  const users = data?.items ?? [];
  const columns: ColumnsType<UserItem> = [
    { title: "UID", dataIndex: "id", width: 230, ellipsis: true },
    { title: "平台", dataIndex: "platform", width: 100, ellipsis: true },
    { title: "首次安装日期", dataIndex: "created_at", width: 140, ellipsis: true, render: formatDate },
    { title: "用户身份", dataIndex: "identity", width: 110, ellipsis: true, render: renderUserIdentity },
    { title: "登录账号", width: 260, render: (_, row) => {
      const account = row.email ?? row.device_id ?? "-";
      return <Text ellipsis={{ tooltip: account }} style={{ maxWidth: 240 }}>{account}</Text>;
    } },
  ];

  function applyFilters() {
    setPage(1);
    setFilters(draft);
  }

  function resetFilters() {
    const empty = { q: "", date_from: "", date_to: "" };
    setDraft(empty);
    setFilters(empty);
    setPage(1);
    setDateRangeKey((value) => value + 1);
  }

  return (
    <PagePanel error={error} onRefresh={reload} className="users-page">
      <FilterBar>
        <Input value={draft.q} onChange={(event) => setDraft((current) => ({ ...current, q: event.target.value }))} onPressEnter={applyFilters} placeholder="UID、邮箱或设备号" className="filter-control user-search-control" />
        <Select allowClear value={draft.platform} onChange={(platform) => setDraft((current) => ({ ...current, platform }))} placeholder="平台" className="filter-control" options={userPlatformOptions} />
        <Select allowClear value={draft.identity} onChange={(identity) => setDraft((current) => ({ ...current, identity }))} placeholder="用户身份" className="filter-control" options={identityOptions} />
        <DatePicker.RangePicker key={dateRangeKey} onChange={(_, values) => setDraft((current) => ({ ...current, date_from: values[0], date_to: values[1] }))} />
        <Button className="cyan-button" onClick={applyFilters}>查询</Button>
        <Button onClick={resetFilters}>重置</Button>
      </FilterBar>
      <DataPanel title="用户数据" count={data?.total ?? 0} className="users-table-panel">
        <Table rowKey={(row) => `${row.account_type}-${row.id}`} columns={columns} dataSource={users} loading={loading} size="small" tableLayout="fixed" scroll={{ x: 840, y: "calc(100dvh - 390px)" }} pagination={{ current: page, pageSize: 8, total: data?.total ?? 0, showSizeChanger: false, showTotal: (total) => `共 ${total} 条`, onChange: setPage }} />
      </DataPanel>
    </PagePanel>
  );
}

function FeedbackPage({ session }: { session: AdminSession }) {
  const { data, loading, reload, error } = useAdminData<{ items: FeedbackTicket[] }>("/feedbacks?page_size=100", session);
  const tickets = data?.items ?? [];

  async function updateStatus(ticket: FeedbackTicket, status: FeedbackStatus) {
    await mutate(session, `/feedbacks/${ticket.id}/status`, { method: "PATCH", body: { status } });
    message.success("处理状态已更新");
    reload();
  }

  return (
    <PagePanel error={error} onRefresh={reload}>
      <FilterBar>
        <DatePicker placeholder="开始时间" />
        <DatePicker placeholder="结束时间" />
        <Select placeholder="平台" className="filter-control" options={platformOptions} />
        <Select placeholder="问题类型" className="filter-control" options={feedbackTypeOptions} />
        <Select placeholder="处理状态" className="filter-control" options={feedbackStatusOptions} />
        <Input placeholder="UID 搜索" className="filter-control" />
        <Button className="cyan-button">查询</Button>
        <Button>重置</Button>
      </FilterBar>
      {loading && <Alert message="正在加载反馈" type="info" showIcon />}
      <div className="feedback-list">
        {tickets.map((ticket) => (
          <article className="feedback-card" key={ticket.id}>
            <div className="feedback-card-head">
              <Space>
                <FeedbackStatusTag status={ticket.status} />
                <Tag>{ticket.issue_type}</Tag>
                <Tag>{ticket.module}</Tag>
              </Space>
              <Text>{formatTime(ticket.created_at)}</Text>
            </div>
            <div className="feedback-meta">
              <span>UID：{ticket.uid}</span>
              <span>版本：{ticket.app_version}</span>
              <span>平台：{ticket.platform}</span>
              <span>设备：{ticket.device_model}</span>
              <span>系统：{ticket.os_version}</span>
              <span>邮箱：{ticket.email}</span>
            </div>
            <p>{ticket.message}</p>
            <Space>
              <Button size="small" className="cyan-button" onClick={() => updateStatus(ticket, "processed")}>
                标记为已处理
              </Button>
              <Button size="small" onClick={() => updateStatus(ticket, "ignored")}>
                无需处理
              </Button>
            </Space>
          </article>
        ))}
      </div>
      <div className="feedback-footer">
        <Text>{rangeSummary(tickets.length, "条反馈")}</Text>
        <Pagination size="small" current={1} pageSize={5} total={tickets.length} showSizeChanger={false} />
      </div>
    </PagePanel>
  );
}

function ScansPage({ session }: { session: AdminSession }) {
  const [selected, setSelected] = useState<ScanDetail | null>(null);
  const [page, setPage] = useState(1);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [filters, setFilters] = useState<Record<string, string>>({});
  const queryPath = useMemo(() => {
    const params = new URLSearchParams({ page: String(page), page_size: "10" });
    Object.entries(filters).forEach(([key, value]) => {
      if (value) params.set(key, value);
    });
    return `/scans?${params.toString()}`;
  }, [filters, page]);
  const { data, loading, reload, error } = useAdminData<ScanListResponse>(queryPath, session);
  const scans = data?.items ?? [];

  async function openDetail(scanId: string) {
    const detail = await adminRequest<ScanDetail>(`/scans/${scanId}`, { token: session.accessToken });
    setSelected(detail);
  }

  const columns: ColumnsType<ScanListItem> = [
    { title: "SCAN ID", dataIndex: "scan_id", ellipsis: true },
    { title: "卡牌图片", dataIndex: "image_url", render: (value: string) => <AuthenticatedScanImage path={value} session={session} className="scan-thumb" /> },
    { title: "UID", dataIndex: "uid" },
    { title: "APP版本", dataIndex: "app_version" },
    { title: "扫描时间", dataIndex: "scan_time", render: formatTime },
    { title: "识别状态", dataIndex: "recognition_status", render: renderRecognitionStatus },
    { title: "是否修改结果", dataIndex: "modified_result", render: (value: boolean) => (value ? "是" : "否") },
    { title: "操作", render: (_, row) => <Button type="link" onClick={() => openDetail(row.scan_id)}>查看详情</Button> },
  ];

  return (
    <div className="scans-page">
      {error && <Alert type="error" showIcon message={error} action={<Button onClick={reload}>重试</Button>} />}
      <section className="scans-filter-panel">
        <ScanFilterField label="扫描时间">
          <DatePicker.RangePicker placeholder={["扫描开始", "扫描结束"]} onChange={(_, values) => setDraft((current) => ({ ...current, date_from: values[0], date_to: values[1] }))} />
        </ScanFilterField>
        <ScanFilterField label="UID">
          <Input placeholder="输入用户 ID" value={draft.uid ?? ""} onChange={(event) => setDraft((current) => ({ ...current, uid: event.target.value }))} />
        </ScanFilterField>
        <ScanFilterField label="平台">
          <Select placeholder="全部" allowClear value={draft.platform || undefined} options={scanPlatformOptions} onChange={(value) => setDraft((current) => ({ ...current, platform: value ?? "" }))} />
        </ScanFilterField>
        <ScanFilterField label="App 版本">
          <Input placeholder="e.g. 2.4.0" value={draft.app_version ?? ""} onChange={(event) => setDraft((current) => ({ ...current, app_version: event.target.value }))} />
        </ScanFilterField>
        <ScanFilterField label="识别状态">
          <Select placeholder="全部" allowClear value={draft.recognition_status || undefined} options={recognitionOptions} onChange={(value) => setDraft((current) => ({ ...current, recognition_status: value ?? "" }))} />
        </ScanFilterField>
        <ScanFilterField label="用户确认状态">
          <Select placeholder="全部" allowClear value={draft.user_confirmation_status || undefined} options={confirmationOptions} onChange={(value) => setDraft((current) => ({ ...current, user_confirmation_status: value ?? "" }))} />
        </ScanFilterField>
        <ScanFilterField label="是否修改结果">
          <Select placeholder="全部" allowClear value={draft.modified_result || undefined} options={[{ value: "true", label: "是" }, { value: "false", label: "否" }]} onChange={(value) => setDraft((current) => ({ ...current, modified_result: value ?? "" }))} />
        </ScanFilterField>
        <div className="scans-filter-actions">
          <Button className="cyan-button" onClick={() => { setPage(1); setFilters(draft); }}>查询</Button>
          <Button onClick={() => { setDraft({}); setFilters({}); setPage(1); }}>重置</Button>
        </div>
      </section>
      <section className="scans-table-panel">
        <Table rowKey="scan_id" columns={columns} dataSource={scans} loading={loading} pagination={false} />
        <div className="scans-pagination">
          <Text>{rangeSummaryPage(page, data?.page_size ?? 10, data?.total ?? 0)}</Text>
          <Pagination size="small" current={page} pageSize={data?.page_size ?? 10} total={data?.total ?? 0} showSizeChanger={false} onChange={setPage} />
        </div>
      </section>
      <p className="scans-data-note">ⓘ 数据用途说明：扫描图片和识别结果仅用于问题排查、支持与识别质量审计。</p>
      <ScanDetailDrawer scan={selected} session={session} onClose={() => setSelected(null)} />
    </div>
  );
}

function ScanFilterField({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="scan-filter-field"><span>{label}</span>{children}</label>;
}

function PermissionsPage({ session }: { session: AdminSession }) {
  const [modalOpen, setModalOpen] = useState(false);
  const [form] = Form.useForm();
  const { data, loading, reload, error } = useAdminData<{ items: PermissionItem[] }>("/permissions?page_size=100", session);
  const permissions = data?.items ?? [];

  async function savePermission(values: { email: string; role: AdminRole; password: string }) {
    await mutate(session, "/permissions", { method: "POST", body: values });
    setModalOpen(false);
    form.resetFields();
    reload();
  }

  async function togglePermission(row: PermissionItem) {
    await mutate(session, `/permissions/${row.id}`, {
      method: "PATCH",
      body: { status: row.permission_status === "active" ? "disabled" : "active" },
    });
    reload();
  }

  const columns: ColumnsType<PermissionItem> = [
    { title: "邮箱账号", dataIndex: "email" },
    { title: "权限状态", dataIndex: "permission_status", render: renderPermissionStatus },
    { title: "添加时间", dataIndex: "created_at", render: formatDate },
    { title: "更新时间", dataIndex: "updated_at", render: formatDate },
    {
      title: "操作",
      render: (_, row) => (
        <Space>
          <Button type="link">编辑</Button>
          <Button type="link" danger={row.permission_status === "active"} onClick={() => togglePermission(row)}>
            {row.permission_status === "active" ? "停用" : "启用"}
          </Button>
        </Space>
      ),
    },
  ];

  return (
    <PagePanel error={error} onRefresh={reload}>
      <section className="rules-box">
        <Title level={5}>权限规则说明</Title>
        <Text>只有授权账号可登录后台；停用账号将无法访问后台。</Text>
      </section>
      <div className="toolbar-row">
        <FilterBar>
          <Input placeholder="邮箱账号" className="filter-control" />
          <Select placeholder="权限状态" className="filter-control" options={permissionStatusOptions} />
          <Button className="cyan-button">查询</Button>
          <Button>重置</Button>
        </FilterBar>
        <Button className="cyan-button" onClick={() => setModalOpen(true)}>
          新增授权账号
        </Button>
      </div>
      <DataPanel title="授权账号" count={permissions.length}>
        <Table rowKey="id" columns={columns} dataSource={permissions} loading={loading} pagination={{ pageSize: 8 }} />
      </DataPanel>
      <Modal open={modalOpen} title="新增授权账号" onCancel={() => setModalOpen(false)} onOk={form.submit}>
        <Form form={form} layout="vertical" onFinish={savePermission} initialValues={{ role: "operator" }}>
          <Form.Item name="email" label="邮箱账号" rules={[{ required: true, type: "email" }]}>
            <Input />
          </Form.Item>
          <Form.Item name="role" label="账号角色" rules={[{ required: true }]}>
            <Select options={[{ value: "operator", label: "运营管理员" }, { value: "super_admin", label: "超级管理员" }]} />
          </Form.Item>
          <Form.Item name="password" label="初始密码" rules={[{ required: true }]}>
            <Input.Password />
          </Form.Item>
        </Form>
      </Modal>
    </PagePanel>
  );
}

function AppVersionsPage({ session }: { session: AdminSession }) {
  const [editing, setEditing] = useState<AppVersionItem | null>(null);
  const [form] = Form.useForm<AppVersionItem>();
  const { data, loading, reload, error } = useAdminData<{ items: AppVersionItem[] }>("/app-versions", session);

  useEffect(() => {
    if (editing) form.setFieldsValue(editing);
  }, [editing, form]);

  async function saveVersion(values: AppVersionItem) {
    if (!editing) return;
    await mutate(session, `/app-versions/${editing.platform}`, { method: "PATCH", body: values });
    setEditing(null);
    reload();
  }

  async function toggleVersion(row: AppVersionItem) {
    await mutate(session, `/app-versions/${row.platform}`, {
      method: "PATCH",
      body: { ...row, status: row.status === "enabled" ? "disabled" : "enabled" },
    });
    reload();
  }

  const columns: ColumnsType<AppVersionItem> = [
    { title: "操作平台", dataIndex: "platform" },
    { title: "最低支持版本", dataIndex: "min_supported_version" },
    { title: "建议更新版本", dataIndex: "recommended_version", render: (value: string) => <Text className="accent-text">{value}</Text> },
    { title: "强制更新", dataIndex: "force_update", render: (value: boolean) => value ? "开启" : "关闭" },
    { title: "更新时间", dataIndex: "updated_at", render: formatDate },
    { title: "状态", dataIndex: "status", render: renderAppVersionStatus },
    {
      title: "操作",
      render: (_, row) => (
        <Space>
          <Button type="link" onClick={() => setEditing(row)}>
            编辑
          </Button>
          <Button type="link" danger={row.status === "enabled"} onClick={() => toggleVersion(row)}>
            {row.status === "enabled" ? "禁用" : "启用"}
          </Button>
        </Space>
      ),
    },
  ];

  return (
    <PagePanel error={error} onRefresh={reload}>
      <div className="top-tabs">
        <span>销售数据</span>
        <span>订单查询</span>
        <strong>版本管理</strong>
      </div>
      <section className="table-panel narrow-table">
        <Table rowKey="platform" columns={columns} dataSource={data?.items ?? []} loading={loading} pagination={false} />
      </section>
      <Drawer
        open={!!editing}
        title="编辑版本管理"
        width={520}
        closable={false}
        onClose={() => setEditing(null)}
        extra={<Button type="text" onClick={() => setEditing(null)}>×</Button>}
      >
        <Form form={form} layout="vertical" onFinish={saveVersion} requiredMark={false}>
          <Form.Item name="platform" label="操作平台">
            <Input disabled />
          </Form.Item>
          <div className="two-col-form">
            <Form.Item name="min_supported_version" label="最低支持版本" rules={[{ pattern: /^\d+\.\d+\.\d+$/, message: "请输入数字或英文点号" }]}>
              <Input />
            </Form.Item>
            <Form.Item name="recommended_version" label="建议更新版本" rules={[{ pattern: /^\d+\.\d+\.\d+$/, message: "请输入数字或英文点号" }]}>
              <Input />
            </Form.Item>
          </div>
          <Form.Item name="force_update" label="强制更新" valuePropName="checked">
            <Switch />
          </Form.Item>
          <Form.Item name="store_url" label="应用商店地址" rules={[{ type: "url", message: "请输入有效的 HTTP(S) 地址" }]}>
            <Input placeholder="https://..." />
          </Form.Item>
          <Form.Item name="recommended_update_message" label="建议更新文案">
            <TextArea rows={5} />
          </Form.Item>
          <Form.Item name="forced_update_message" label="强制更新文案">
            <TextArea rows={5} />
          </Form.Item>
          <Form.Item name="status" label="状态">
            <Select options={[{ value: "enabled", label: "生效中" }, { value: "disabled", label: "已停用" }]} />
          </Form.Item>
          <div className="drawer-footer">
            <Button onClick={() => setEditing(null)}>取消</Button>
            <Button className="cyan-button" htmlType="submit">
              保存
            </Button>
          </div>
        </Form>
      </Drawer>
    </PagePanel>
  );
}

function ScanDetailDrawer({ scan, session, onClose }: { scan: ScanDetail | null; session: AdminSession; onClose: () => void }) {
  return (
    <Drawer open={!!scan} onClose={onClose} title="扫描详情" width={560} className="scan-detail-drawer">
      {scan && (
        <Space direction="vertical" size={20} className="drawer-stack">
          <DetailSection title="扫描图片">
            <AuthenticatedScanImage path={scan.image_url} session={session} className="scan-preview" />
            <Input value={scan.image_url ? "Private R2 scan image" : "-"} readOnly addonAfter="受控访问" />
          </DetailSection>
          <DetailSection title="基础信息">
            <InfoGrid items={[
              { label: "Scan ID", value: scan.scan_id },
              { label: "UID", value: scan.uid },
              { label: "平台", value: scan.platform },
              { label: "App 版本", value: scan.app_version },
              { label: "设备型号", value: scan.device_model },
              { label: "系统版本", value: scan.os_version },
              { label: "扫描时间", value: formatTime(scan.scan_time) },
            ]} />
          </DetailSection>
          <DetailSection title="系统识别结果">
            <InfoGrid items={[
              { label: "状态", value: renderRecognitionStatus(String(scan.system_result.status ?? scan.recognition_status)) },
              { label: "名称", value: displayValue(scan.system_result.name) },
              { label: "IP / Game", value: displayValue(scan.system_result.ip_game) },
              { label: "Set", value: displayValue(scan.system_result.set) },
              { label: "Number", value: displayValue(scan.system_result.number) },
              { label: "置信度", value: confidenceText(scan.system_result.confidence) },
              { label: "候选数量", value: displayValue(scan.system_result.candidate_count) },
            ]} />
          </DetailSection>
          <DetailSection title="用户确认结果">
            <InfoGrid items={[
              { label: "确认状态", value: displayValue(scan.user_result.confirmation_status ?? scan.user_confirmation_status) },
              { label: "最终卡牌", value: displayValue(scan.user_result.final_card) },
              { label: "是否修改", value: displayValue(scan.user_result.modified_result ?? scan.modified_result) },
              { label: "加入库存", value: displayValue(scan.user_result.added_to_inventory) },
              { label: "加入愿望单", value: displayValue(scan.user_result.added_to_wishlist) },
            ]} />
          </DetailSection>
          <DetailSection title="候选识别结果">
            <div className="candidate-list">
              {scan.candidates.map((candidate, index) => (
                <div className="candidate-card" key={index}>
                  <span className="candidate-thumb" />
                  <div>
                    <strong>{displayValue(candidate.name)}</strong>
                    <Text>{displayValue(candidate.set_code ?? candidate.set)} {displayValue(candidate.card_number ?? candidate.number)} · {confidenceText(candidate.confidence)}</Text>
                  </div>
                </div>
              ))}
            </div>
          </DetailSection>
        </Space>
      )}
    </Drawer>
  );
}

function AuthenticatedScanImage({ path, session, className }: { path: string; session: AdminSession; className: string }) {
  const [source, setSource] = useState<string | null>(null);
  useEffect(() => {
    if (!path) {
      setSource(null);
      return;
    }
    let active = true;
    let objectUrl: string | null = null;
    fetch(`${API_BASE}${path}`, { headers: { Authorization: `Bearer ${session.accessToken}` } })
      .then((response) => {
        dispatchSessionExpiredOnUnauthorized(response, session.accessToken);
        if (!response.ok) throw new Error("Scan image unavailable");
        return response.blob();
      })
      .then((blob) => {
        if (!active) return;
        objectUrl = URL.createObjectURL(blob);
        setSource(objectUrl);
      })
      .catch(() => { if (active) setSource(null); });
    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [path, session.accessToken]);
  return source
    ? <img className={className} src={source} alt="扫描卡牌" />
    : <span className={`${className} scan-image-placeholder`} aria-label="图片未存储" />;
}

function DetailSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="detail-section">
      <Title level={5}>{title}</Title>
      {children}
    </section>
  );
}

function InfoGrid({ items }: { items: Array<{ label: string; value: React.ReactNode }> }) {
  return (
    <div className="info-grid">
      {items.map((item) => (
        <div className="info-item" key={item.label}>
          <Text>{item.label}</Text>
          <strong>{item.value}</strong>
        </div>
      ))}
    </div>
  );
}

function DataPanel({ title, count, children, className = "" }: { title: string; count?: number; children: React.ReactNode; className?: string }) {
  return (
    <section className={`table-panel ${className}`.trim()}>
      <div className="panel-heading">
        <Title level={4}>{title}</Title>
        {count !== undefined && <Text>共 {count.toLocaleString()} 条结果</Text>}
      </div>
      {children}
    </section>
  );
}

function PagePanel({ error, onRefresh, children, className = "" }: { error: string | null; onRefresh: () => void; children: React.ReactNode; className?: string }) {
  return (
    <div className={`page-panel ${className}`.trim()}>
      <div className="refresh-row">
        <span />
        <Button onClick={onRefresh}>刷新</Button>
      </div>
      {error && <Alert type="error" showIcon message={error} />}
      {children}
    </div>
  );
}

function FilterBar({ children }: { children: React.ReactNode }) {
  return <section className="filter-bar">{children}</section>;
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div className="metric-box">
      <Text>{label}</Text>
      <strong>{value.toLocaleString()}</strong>
    </div>
  );
}

function LineChart({ data }: { data: Array<{ date: string; total: number }> }) {
  const points = data.length > 0 ? data : [{ date: "1d", total: 0 }, { date: "7d", total: 0 }, { date: "15d", total: 0 }, { date: "1m", total: 0 }, { date: "3m", total: 0 }];
  const max = Math.max(...points.map((item) => item.total), 1);
  const path = points
    .map((item, index) => {
      const x = 36 + (index * 672) / Math.max(points.length - 1, 1);
      const y = 180 - (item.total / max) * 120;
      return `${index === 0 ? "M" : "L"} ${x} ${y}`;
    })
    .join(" ");

  return (
    <svg className="line-chart" viewBox="0 0 760 220" role="img" aria-label="安装趋势">
      {[40, 80, 120, 160, 200].map((y) => <line key={y} x1="28" x2="728" y1={y} y2={y} />)}
      <path d={path} />
      {points.map((item, index) => {
        const x = 36 + (index * 672) / Math.max(points.length - 1, 1);
        const y = 180 - (item.total / max) * 120;
        return (
          <g key={`${item.date}-${index}`}>
            <circle cx={x} cy={y} r="4" />
            <text x={x} y="208">{index < PERIOD_OPTIONS.length ? PERIOD_OPTIONS[index] : item.date.slice(5)}</text>
          </g>
        );
      })}
    </svg>
  );
}

function useAdminData<T>(path: string, session: AdminSession) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError(null);
    adminRequest<T>(path, { token: session.accessToken })
      .then((nextData) => {
        if (alive) setData(nextData);
      })
      .catch((requestError) => {
        if (alive) setError(errorMessage(requestError));
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [path, session.accessToken, version]);

  return useMemo(() => ({ data, loading, error, reload: () => setVersion((value) => value + 1) }), [data, error, loading]);
}

function mutate(session: AdminSession, path: string, init: AdminRequestInit) {
  return adminRequest(path, { ...init, token: session.accessToken });
}

async function adminRequest<T>(path: string, init: AdminRequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.token) headers.set("Authorization", `Bearer ${init.token}`);
  if (init.body !== undefined) headers.set("Content-Type", "application/json");

  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  dispatchSessionExpiredOnUnauthorized(response, init.token);
  const payload = (await response.json()) as ApiResponse<T>;
  if (!response.ok || !payload.success) {
    if (payload.success) throw new AdminApiError("REQUEST_FAILED", "请求失败");
    throw new AdminApiError(payload.error.code, payload.error.message);
  }
  return payload.data;
}

function dispatchSessionExpiredOnUnauthorized(response: Response, token?: string) {
  if (token && response.status === 401) {
    window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT));
  }
}

class AdminApiError extends Error {
  constructor(readonly code: string, messageText: string) {
    super(messageText);
  }
}

function readStoredSession(): AdminSession | null {
  try {
    const value = window.localStorage.getItem(SESSION_STORAGE_KEY);
    return value ? (JSON.parse(value) as AdminSession) : null;
  } catch {
    return null;
  }
}

function FeedbackStatusTag({ status }: { status: FeedbackStatus }) {
  const map = {
    pending: { color: "gold", text: "待处理" },
    processed: { color: "green", text: "已处理" },
    ignored: { color: "default", text: "无需处理" },
  } satisfies Record<FeedbackStatus, { color: string; text: string }>;
  return <Tag color={map[status].color}>{map[status].text}</Tag>;
}

function renderPermissionStatus(value: PermissionStatus) {
  return value === "active" ? <Badge status="success" text="启用" /> : <Badge status="default" text="停用" />;
}

function renderAppVersionStatus(value: AppVersionStatus) {
  return value === "enabled" ? <Tag color="green">生效中</Tag> : <Tag>已停用</Tag>;
}

function renderRecognitionStatus(value: string) {
  if (value === "success") return <Tag color="cyan">识别成功</Tag>;
  if (value === "no_match") return <Tag color="gold">未命中</Tag>;
  return <Tag color="red">识别失败</Tag>;
}

function renderUserIdentity(value: UserItem["identity"]) {
  const labels = { anonymous: "游客", email: "邮箱", google: "Google", apple: "Apple" };
  const colors = { anonymous: "default", email: "cyan", google: "blue", apple: "purple" };
  return <Tag color={colors[value]}>{labels[value]}</Tag>;
}

function formatDate(value: string | null) {
  return value ? value.slice(0, 10) : "-";
}

function formatTime(value: string | null) {
  return value ? new Date(value).toLocaleString() : "-";
}

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === "") return "-";
  if (typeof value === "boolean") return value ? "是" : "否";
  return String(value);
}

function confidenceText(value: unknown) {
  const numeric = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numeric)) return displayValue(value);
  const rounded = Math.round(numeric * 1000) / 1000;
  return `${rounded.toFixed(3).replace(/\.?0+$/, "")}%`;
}

function rangeSummaryPage(page: number, pageSize: number, total: number) {
  if (total === 0) return "显示 0 条，共 0 条";
  const start = (page - 1) * pageSize + 1;
  const end = Math.min(page * pageSize, total);
  return `显示 ${start}-${end} 条，共 ${total.toLocaleString()} 条`;
}

function rangeSummary(count: number, unit: string) {
  if (count === 0) return `显示 0 条，共 0 ${unit}`;
  return `显示 1 到 ${count} 条，共 ${count.toLocaleString()} ${unit}`;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "请求失败，请稍后重试";
}

const countryOptions = ["United States", "Canada", "United Kingdom", "Japan", "Australia"].map((value) => ({ value, label: value }));
const platformOptions = ["iOS", "Google"].map((value) => ({ value, label: value }));
const environmentOptions = [{ value: "production", label: "Production" }, { value: "staging", label: "Staging" }];
const userPlatformOptions = ["iOS", "Android", "web"].map((value) => ({ value, label: value }));
const identityOptions = [
  { value: "google", label: "Google" }, { value: "anonymous", label: "游客" },
  { value: "apple", label: "Apple" }, { value: "email", label: "邮箱" },
];
const feedbackTypeOptions = ["Bug Report", "Feature Request", "Account", "Other"].map((value) => ({ value, label: value }));
const feedbackStatusOptions = [
  { value: "pending", label: "待处理" },
  { value: "processed", label: "已处理" },
  { value: "ignored", label: "无需处理" },
];
const recognitionOptions = [
  { value: "success", label: "识别成功" },
  { value: "no_match", label: "未命中" },
  { value: "failed", label: "识别失败" },
];
const scanPlatformOptions = ["iOS", "Android", "web"].map((value) => ({ value, label: value }));
const confirmationOptions = [{ value: "confirmed", label: "已确认" }, { value: "pending", label: "待确认" }];
const permissionStatusOptions = [{ value: "active", label: "启用" }, { value: "disabled", label: "停用" }];
