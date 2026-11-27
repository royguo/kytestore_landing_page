# KyteStore Landing Page

本仓库是 KyteStore 官网静态站点，由阿里云 ECS 上的 Nginx 提供服务。

## 维护规则

- 每个页面更新后，都要检查其他对应页面是否也需要同步更新。重点包括导航栏、中英文文案、meta 信息、博客链接、`sitemap.xml`、以及 `public/` 部署副本。
- 源页面位于仓库根目录和 `blog/` 目录。部署使用 `public/` 中的镜像文件，因此每次内容变更都必须同步到对应的 `public/` 文件后再提交。
- `sitemap.xml` 和 `public/sitemap.xml` 必须反映当前公开 URL 结构。重要页面内容变更后，要同步更新对应 URL 的 `lastmod`。
- 所有面向用户的正文内容都必须同时维护中文和英文版本。新增或修改中文内容后，要同步翻译到英文视图；新增或修改英文内容后，也要同步回中文视图，避免语言切换后信息缺失。
- 博客编写要尽可能多使用图例、例子和分步骤说明。不要假设读者已经理解 KyteStore 的技术名词，应该先用通用存储概念解释，再引入 KyteStore 的具体设计。
- 博客的目的是向客户展示 KyteStore 的技术先进性、架构取舍和方案合理性。
- 博客应尽可能引用或对比社区与知名厂商的公开方案选型，包括但不限于 Ceph、Weka、VAST、Alluxio、JuiceFS、Jindo、MinIO、SeaweedFS、FoundationDB 等。
- 涉及竞品或社区方案时，优先使用官方文档、论文、设计文档、工程博客等一手资料，避免没有来源支撑的判断。

## ECS 部署

将已提交的 `public/` 内容发布到 `/srv/kytestore-site/releases/<commit>`。
Nginx 使用 [站点配置](deploy/nginx.conf)，通过 `server_name kytestore.com`
选择站点，读取 `/srv/kytestore-site/current`。更新时原子替换此链接，
然后验证首页、博客和下载。回滚时将链接切回上一版。

裸域在 Cloudflare 发布仅 DNS 的 A 记录。Certbot 通过
`/var/lib/kytestore-acme` 完成域名验证，证书更新成功后重载 Nginx。

## 文档规则

- 日常改进记录统一放在 `docs/worklog/` 目录。
- 工作日志使用 Markdown 编写，文件名采用 `YYYY-MM-DD.md` 格式，例如 `docs/worklog/2026-06-24.md`。
- 工作日志应记录当天完成的用户可见改进、内容更新、验证结果和必要的后续事项。
- 如果一次改动涉及源文件和 `public/` 部署副本，工作日志中应明确两者是否都已同步。
- 不要把临时想法、未验证判断或敏感凭据写入工作日志。
