import { Typography } from "antd";

const { Title, Paragraph } = Typography;

// M0 占位页：后台各模块（用户/工单/运营配置/卡牌覆盖）在 M7 落地。
export default function App() {
  return (
    <div style={{ padding: 24 }}>
      <Title level={2}>Kando Admin</Title>
      <Paragraph>M0 工程骨架占位页。</Paragraph>
    </div>
  );
}
