import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        onlyExplicitManualChunks: true,
        manualChunks(id) {
          if (!id.includes("node_modules")) return;
          if (/[\\/]react(?:-dom)?[\\/]|[\\/]scheduler[\\/]/.test(id)) return "react-vendor";
          if (id.includes("@tanstack")) return "query-vendor";
          if (id.includes("@babel/runtime")) return "antd-rc";
          if (id.includes("@rc-component") || /[\\/]rc-[^\\/]+[\\/]/.test(id)) return "antd-rc";
          if (id.includes("@ant-design")) return "antd-rc";
          if (/[\\/]antd[\\/]/.test(id)) return "antd-vendor";
          if (/[\\/]dayjs[\\/]/.test(id)) return "date-vendor";
        },
      },
    },
  },
});
