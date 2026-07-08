import {
  Alert,
  Button,
  Drawer,
  Form,
  Input,
  InputNumber,
  Layout,
  Menu,
  Modal,
  Popconfirm,
  Select,
  Space,
  Switch,
  Table,
  Tabs,
  Tag,
  Typography,
  message,
} from "antd";
import type { ColumnsType } from "antd/es/table";
import { useEffect, useMemo, useState } from "react";

type AdminRole = "super_admin" | "operator";
type MenuKey = "users" | "feedbacks" | "app-config" | "trending-pins" | "card-overrides";

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

type UserItem = {
  account_type: "user" | "anonymous";
  id: string;
  email: string | null;
  device_id: string | null;
  created_at: string;
  status: "active" | "disabled" | "guest" | "upgraded";
};

type FeedbackStatus = "open" | "in_progress" | "closed";

type FeedbackTicket = {
  id: string;
  email: string;
  types: string;
  functions: string;
  message: string;
  status: FeedbackStatus;
  created_at: string;
  updated_at: string;
};

type AppConfigItem = {
  key: string;
  value: string;
  updated_by: string | null;
  updated_at: string;
};

type TrendingPin = {
  id: string;
  card_ref: string;
  rank: number;
  active: number;
  updated_by: string | null;
  updated_at: string;
};

type CardOverride = {
  id: string;
  card_ref: string;
  override_fields: string | null;
  image_url: string | null;
  is_missing_card: number;
  updated_by: string | null;
  updated_at: string;
};

const { Header, Sider, Content } = Layout;
const { Title, Text } = Typography;
const { TextArea } = Input;
const API_BASE = "/api/v1/admin";
const SESSION_STORAGE_KEY = "kando_admin_session";

const menuItems: Array<{ key: MenuKey; label: string }> = [
  { key: "users", label: "用户管理" },
  { key: "feedbacks", label: "反馈工单" },
  { key: "app-config", label: "运营配置" },
  { key: "trending-pins", label: "Trending Pin" },
  { key: "card-overrides", label: "卡牌覆盖" },
];

export default function App() {
  const [session, setSession] = useState<AdminSession | null>(() => readStoredSession());

  useEffect(() => {
    if (session) {
      window.localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
    } else {
      window.localStorage.removeItem(SESSION_STORAGE_KEY);
    }
  }, [session]);

  if (!session) {
    return <LoginView onLogin={setSession} />;
  }

  return <AdminShell session={session} onLogout={() => setSession(null)} />;
}

function LoginView({ onLogin }: { onLogin: (session: AdminSession) => void }) {
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
      message.error(errorMessage(error));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Layout style={{ minHeight: "100vh", background: "#f5f7fb" }}>
      <Content style={{ display: "grid", placeItems: "center", padding: 24 }}>
        <div style={{ width: "100%", maxWidth: 360 }}>
          <Title level={3} style={{ marginBottom: 24 }}>
            Kando Admin
          </Title>
          <Form layout="vertical" onFinish={handleFinish} requiredMark={false}>
            <Form.Item name="email" label="邮箱" rules={[{ required: true }]}>
              <Input autoComplete="email" />
            </Form.Item>
            <Form.Item name="password" label="密码" rules={[{ required: true }]}>
              <Input.Password autoComplete="current-password" />
            </Form.Item>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              登录
            </Button>
          </Form>
        </div>
      </Content>
    </Layout>
  );
}

function AdminShell({
  session,
  onLogout,
}: {
  session: AdminSession;
  onLogout: () => void;
}) {
  const [selected, setSelected] = useState<MenuKey>("users");

  return (
    <Layout style={{ minHeight: "100vh" }}>
      <Sider breakpoint="lg" collapsedWidth={0} theme="light">
        <div style={{ height: 56, display: "flex", alignItems: "center", padding: "0 20px" }}>
          <Text strong>Kando Admin</Text>
        </div>
        <Menu
          mode="inline"
          selectedKeys={[selected]}
          items={menuItems}
          onClick={(item) => setSelected(item.key as MenuKey)}
        />
      </Sider>
      <Layout>
        <Header
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            background: "#fff",
            paddingInline: 24,
            borderBottom: "1px solid #edf0f5",
          }}
        >
          <Space>
            <Text strong>{session.email}</Text>
            <RoleTag role={session.role} />
          </Space>
          <Button onClick={onLogout}>退出</Button>
        </Header>
        <Content style={{ padding: 24, background: "#f5f7fb" }}>
          {selected === "users" && <UsersPage session={session} />}
          {selected === "feedbacks" && <FeedbackPage session={session} />}
          {selected === "app-config" && <AppConfigPage session={session} />}
          {selected === "trending-pins" && <TrendingPinsPage session={session} />}
          {selected === "card-overrides" && <CardOverridesPage session={session} />}
        </Content>
      </Layout>
    </Layout>
  );
}

function UsersPage({ session }: { session: AdminSession }) {
  const [type, setType] = useState<string>();
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<UserItem | null>(null);
  const { data, loading, reload, error } = useAdminData<{ items: UserItem[] }>(
    `/users${toQuery({ type, q: query })}`,
    session,
  );

  async function disableUser(id: string) {
    await mutate(session, `/users/user/${id}/disable`, { method: "PATCH", body: {} });
    message.success("账号已禁用");
    reload();
  }

  const columns: ColumnsType<UserItem> = [
    { title: "账号类型", dataIndex: "account_type", render: renderAccountType },
    { title: "账号 ID", dataIndex: "id", ellipsis: true },
    { title: "邮箱", dataIndex: "email", render: dash },
    { title: "设备 ID", dataIndex: "device_id", render: dash },
    { title: "状态", dataIndex: "status", render: renderUserStatus },
    { title: "注册时间", dataIndex: "created_at", render: formatTime },
    {
      title: "操作",
      render: (_, row) => (
        <Space>
          <Button size="small" onClick={() => setSelected(row)}>
            详情
          </Button>
          {session.role === "super_admin" && row.account_type === "user" && row.status !== "disabled" && (
            <Popconfirm title="禁用账号" description="确认禁用该用户？" onConfirm={() => disableUser(row.id)}>
              <Button size="small" danger>
                禁用
              </Button>
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ];

  return (
    <Section title="用户管理" error={error} onRefresh={reload}>
      <Space style={{ marginBottom: 16 }} wrap>
        <Select
          allowClear
          value={type}
          placeholder="账号类型"
          style={{ width: 180 }}
          options={[
            { value: "user", label: "正式账号" },
            { value: "anonymous", label: "匿名账号" },
          ]}
          onChange={setType}
        />
        <Input.Search
          allowClear
          placeholder="email / device_id"
          style={{ width: 260 }}
          onSearch={setQuery}
        />
      </Space>
      <Table rowKey="id" columns={columns} dataSource={data?.items ?? []} loading={loading} pagination={false} />
      <Drawer open={!!selected} onClose={() => setSelected(null)} title="用户详情" width={420}>
        {selected && <DescriptionRows rows={Object.entries(selected)} />}
      </Drawer>
    </Section>
  );
}

function FeedbackPage({ session }: { session: AdminSession }) {
  const [status, setStatus] = useState<string>();
  const { data, loading, reload, error } = useAdminData<{ items: FeedbackTicket[] }>(
    `/feedbacks${toQuery({ status })}`,
    session,
  );

  async function updateStatus(id: string, nextStatus: FeedbackStatus) {
    await mutate(session, `/feedbacks/${id}/status`, {
      method: "PATCH",
      body: { status: nextStatus },
    });
    message.success("状态已更新");
    reload();
  }

  const columns: ColumnsType<FeedbackTicket> = [
    { title: "工单 ID", dataIndex: "id", ellipsis: true },
    { title: "联系邮箱", dataIndex: "email" },
    { title: "反馈类型", dataIndex: "types", render: renderJsonTags },
    { title: "功能模块", dataIndex: "functions", render: renderJsonTags },
    { title: "状态", dataIndex: "status", render: renderFeedbackStatus },
    { title: "提交时间", dataIndex: "created_at", render: formatTime },
    {
      title: "流转",
      render: (_, row) => (
        <Select
          size="small"
          value={row.status}
          style={{ width: 150 }}
          options={[
            { value: "open", label: "Open" },
            { value: "in_progress", label: "In Progress" },
            { value: "closed", label: "Closed" },
          ]}
          onChange={(value) => updateStatus(row.id, value)}
        />
      ),
    },
  ];

  return (
    <Section title="反馈工单" error={error} onRefresh={reload}>
      <Tabs
        activeKey={status ?? "all"}
        onChange={(key) => setStatus(key === "all" ? undefined : key)}
        items={[
          { key: "all", label: "全部" },
          { key: "open", label: "Open" },
          { key: "in_progress", label: "In Progress" },
          { key: "closed", label: "Closed" },
        ]}
      />
      <Table rowKey="id" columns={columns} dataSource={data?.items ?? []} loading={loading} pagination={false} />
    </Section>
  );
}

function AppConfigPage({ session }: { session: AdminSession }) {
  const [editing, setEditing] = useState<AppConfigItem | null>(null);
  const [value, setValue] = useState("");
  const { data, loading, reload, error } = useAdminData<{ configs: AppConfigItem[] }>("/app-config", session);

  async function saveConfig() {
    if (!editing) return;
    await mutate(session, `/app-config/${editing.key}`, {
      method: "PATCH",
      body: { value },
    });
    message.success("配置已保存");
    setEditing(null);
    reload();
  }

  const columns: ColumnsType<AppConfigItem> = [
    { title: "Key", dataIndex: "key" },
    { title: "Value", dataIndex: "value", ellipsis: true },
    { title: "Updated By", dataIndex: "updated_by", render: dash },
    { title: "更新时间", dataIndex: "updated_at", render: formatTime },
    {
      title: "操作",
      render: (_, row) => (
        <Button
          size="small"
          onClick={() => {
            setEditing(row);
            setValue(row.value);
          }}
        >
          编辑
        </Button>
      ),
    },
  ];

  return (
    <Section title="运营配置" error={error} onRefresh={reload}>
      <Table rowKey="key" columns={columns} dataSource={data?.configs ?? []} loading={loading} pagination={false} />
      <Modal open={!!editing} title={editing?.key} onCancel={() => setEditing(null)} onOk={saveConfig}>
        <TextArea value={value} onChange={(event) => setValue(event.target.value)} rows={8} />
      </Modal>
    </Section>
  );
}

function TrendingPinsPage({ session }: { session: AdminSession }) {
  const [form] = Form.useForm();
  const { data, loading, reload, error } = useAdminData<{ items: TrendingPin[] }>("/trending-pins", session);

  async function createPin(values: { card_ref: string; rank: number; active: boolean }) {
    await mutate(session, "/trending-pins", { method: "POST", body: values });
    form.resetFields();
    message.success("置顶已创建");
    reload();
  }

  async function patchPin(row: TrendingPin, changes: Partial<TrendingPin>) {
    await mutate(session, `/trending-pins/${row.id}`, {
      method: "PATCH",
      body: {
        rank: changes.rank ?? row.rank,
        active: (changes.active ?? row.active) === 1,
      },
    });
    reload();
  }

  async function deletePin(id: string) {
    await mutate(session, `/trending-pins/${id}`, { method: "DELETE" });
    message.success("置顶已删除");
    reload();
  }

  const columns: ColumnsType<TrendingPin> = [
    { title: "卡牌标识", dataIndex: "card_ref", ellipsis: true },
    {
      title: "排序",
      dataIndex: "rank",
      render: (_, row) => <InputNumber min={1} value={row.rank} onPressEnter={(event) => patchPin(row, { rank: Number(event.currentTarget.value) })} />,
    },
    {
      title: "状态",
      dataIndex: "active",
      render: (_, row) => <Switch checked={row.active === 1} onChange={(active) => patchPin(row, { active: active ? 1 : 0 })} />,
    },
    { title: "更新时间", dataIndex: "updated_at", render: formatTime },
    {
      title: "操作",
      render: (_, row) =>
        session.role === "super_admin" ? (
          <Popconfirm title="删除置顶" onConfirm={() => deletePin(row.id)}>
            <Button size="small" danger>
              删除
            </Button>
          </Popconfirm>
        ) : null,
    },
  ];

  return (
    <Section title="Trending Pin" error={error} onRefresh={reload}>
      <Form form={form} layout="inline" onFinish={createPin} style={{ marginBottom: 16 }}>
        <Form.Item name="card_ref" rules={[{ required: true }]}>
          <Input placeholder="card_ref" />
        </Form.Item>
        <Form.Item name="rank" rules={[{ required: true }]} initialValue={1}>
          <InputNumber min={1} placeholder="排序" />
        </Form.Item>
        <Form.Item name="active" valuePropName="checked" initialValue>
          <Switch />
        </Form.Item>
        <Button type="primary" htmlType="submit">
          新增
        </Button>
      </Form>
      <Table rowKey="id" columns={columns} dataSource={data?.items ?? []} loading={loading} pagination={false} />
    </Section>
  );
}

function CardOverridesPage({ session }: { session: AdminSession }) {
  const [form] = Form.useForm();
  const [imageTarget, setImageTarget] = useState<CardOverride | null>(null);
  const [imageUrl, setImageUrl] = useState("");
  const { data, loading, reload, error } = useAdminData<{ items: CardOverride[] }>("/card-overrides", session);

  async function createOverride(values: {
    card_ref: string;
    override_fields?: string;
    image_url?: string;
    is_missing_card?: boolean;
  }) {
    await mutate(session, "/card-overrides", {
      method: "POST",
      body: {
        ...values,
        override_fields: parseJsonObject(values.override_fields),
      },
    });
    form.resetFields();
    message.success("覆盖已保存");
    reload();
  }

  async function uploadImage() {
    if (!imageTarget) return;
    await mutate(session, "/card-overrides/image-upload", {
      method: "POST",
      body: { card_ref: imageTarget.card_ref, image_url: imageUrl },
    });
    setImageTarget(null);
    setImageUrl("");
    message.success("图片已更新");
    reload();
  }

  async function deleteOverride(id: string) {
    await mutate(session, `/card-overrides/${id}`, { method: "DELETE" });
    message.success("覆盖已删除");
    reload();
  }

  const columns: ColumnsType<CardOverride> = [
    { title: "卡牌标识", dataIndex: "card_ref", ellipsis: true },
    { title: "覆盖字段", dataIndex: "override_fields", ellipsis: true, render: renderOverrideKeys },
    { title: "图片", dataIndex: "image_url", render: dash },
    { title: "缺失卡", dataIndex: "is_missing_card", render: (value: number) => (value === 1 ? "是" : "否") },
    { title: "更新时间", dataIndex: "updated_at", render: formatTime },
    {
      title: "操作",
      render: (_, row) => (
        <Space>
          <Button
            size="small"
            onClick={() => {
              setImageTarget(row);
              setImageUrl(row.image_url ?? "");
            }}
          >
            补图
          </Button>
          {session.role === "super_admin" && (
            <Popconfirm title="删除覆盖" onConfirm={() => deleteOverride(row.id)}>
              <Button size="small" danger>
                删除
              </Button>
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ];

  return (
    <Section title="卡牌覆盖" error={error} onRefresh={reload}>
      <Form form={form} layout="inline" onFinish={createOverride} style={{ marginBottom: 16 }}>
        <Form.Item name="card_ref" rules={[{ required: true }]}>
          <Input placeholder="card_ref" />
        </Form.Item>
        <Form.Item name="override_fields">
          <Input placeholder='{"name":"..."}' />
        </Form.Item>
        <Form.Item name="image_url">
          <Input placeholder="image_url" />
        </Form.Item>
        <Form.Item name="is_missing_card" valuePropName="checked">
          <Switch checkedChildren="缺失" unCheckedChildren="覆盖" />
        </Form.Item>
        <Button type="primary" htmlType="submit">
          新增
        </Button>
      </Form>
      <Table rowKey="id" columns={columns} dataSource={data?.items ?? []} loading={loading} pagination={false} />
      <Modal open={!!imageTarget} title="补图" onCancel={() => setImageTarget(null)} onOk={uploadImage}>
        <Input value={imageUrl} onChange={(event) => setImageUrl(event.target.value)} placeholder="image_url" />
      </Modal>
    </Section>
  );
}

function Section({
  title,
  error,
  onRefresh,
  children,
}: {
  title: string;
  error: string | null;
  onRefresh: () => void;
  children: React.ReactNode;
}) {
  return (
    <div style={{ background: "#fff", border: "1px solid #edf0f5", borderRadius: 8, padding: 20 }}>
      <Space style={{ display: "flex", justifyContent: "space-between", marginBottom: 16 }}>
        <Title level={4} style={{ margin: 0 }}>
          {title}
        </Title>
        <Button onClick={onRefresh}>刷新</Button>
      </Space>
      {error && <Alert type="error" showIcon message={error} style={{ marginBottom: 16 }} />}
      {children}
    </div>
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

  return useMemo(
    () => ({ data, loading, error, reload: () => setVersion((value) => value + 1) }),
    [data, error, loading],
  );
}

function mutate(session: AdminSession, path: string, init: AdminRequestInit) {
  return adminRequest(path, { ...init, token: session.accessToken });
}

async function adminRequest<T>(
  path: string,
  init: AdminRequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.token) headers.set("Authorization", `Bearer ${init.token}`);
  if (init.body !== undefined) headers.set("Content-Type", "application/json");

  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const payload = (await response.json()) as ApiResponse<T>;
  if (!response.ok || !payload.success) {
    throw new Error(payload.success ? "请求失败" : payload.error.message);
  }
  return payload.data;
}

function toQuery(values: Record<string, string | undefined>) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) {
    if (value) params.set(key, value);
  }
  const query = params.toString();
  return query ? `?${query}` : "";
}

function readStoredSession(): AdminSession | null {
  try {
    const value = window.localStorage.getItem(SESSION_STORAGE_KEY);
    return value ? (JSON.parse(value) as AdminSession) : null;
  } catch {
    return null;
  }
}

function renderAccountType(value: UserItem["account_type"]) {
  return value === "user" ? "正式账号" : "匿名账号";
}

function renderUserStatus(value: UserItem["status"]) {
  const color = value === "active" || value === "guest" ? "green" : value === "disabled" ? "red" : "blue";
  return <Tag color={color}>{value}</Tag>;
}

function renderFeedbackStatus(value: FeedbackStatus) {
  const color = value === "open" ? "blue" : value === "in_progress" ? "orange" : "default";
  return <Tag color={color}>{value}</Tag>;
}

function RoleTag({ role }: { role: AdminRole }) {
  return <Tag color={role === "super_admin" ? "red" : "blue"}>{role}</Tag>;
}

function renderJsonTags(value: string) {
  const values = parseJsonArray(value);
  return (
    <Space wrap size={[4, 4]}>
      {values.map((item) => (
        <Tag key={item}>{item}</Tag>
      ))}
    </Space>
  );
}

function renderOverrideKeys(value: string | null) {
  if (!value) return "—";
  const parsed = parseJsonObject(value);
  return parsed ? Object.keys(parsed).join(", ") : value;
}

function DescriptionRows({ rows }: { rows: Array<[string, unknown]> }) {
  return (
    <Space direction="vertical" style={{ width: "100%" }}>
      {rows.map(([key, value]) => (
        <div key={key} style={{ display: "grid", gridTemplateColumns: "120px 1fr", gap: 12 }}>
          <Text type="secondary">{key}</Text>
          <Text>{String(value ?? "—")}</Text>
        </div>
      ))}
    </Space>
  );
}

function parseJsonArray(value: string) {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.map(String) : [];
  } catch {
    return [];
  }
}

function parseJsonObject(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "string" || value.trim().length === 0) return null;
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function formatTime(value: string | null) {
  return value ? new Date(value).toLocaleString() : "—";
}

function dash(value: unknown) {
  return value || "—";
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Something went wrong. Please try again.";
}
