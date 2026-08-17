# Taiwan Subsidy F

F 项目独立静态站点：

- `index.html`：4 步补助申请落地页
- `admin.html`：独立管理员后台，包含订单管理、LINE 配置和 Facebook Pixel 配置
- `supabase-schema.sql`：只管理 `f_subsidy_leads` 与 `f_site_settings`，不修改 A、B 或其他数据表

客户输入不做格式验证，填写内容会按原样进入 F 项目独立数据表。

客户提交成功后会显示姓名复制与专员 LINE 引导。LINE 链接、显示 ID 和多个 Facebook Pixel ID 均可从后台“系统设置”修改。

Supabase 项目：`xgjnmhedqwehxgwnlggo`。后台使用现有 `admin@taiwan-subsidy.com` Auth 账号登录。
