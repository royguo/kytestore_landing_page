# KyteStore Landing Page

本仓库是 KyteStore 官网静态站点，当前由 Cloudflare 自动部署。

## 维护规则

- 每个页面更新后，都要检查其他对应页面是否也需要同步更新。重点包括导航栏、中英文文案、meta 信息、博客链接、`sitemap.xml`、以及 `public/` 部署副本。
- 源页面位于仓库根目录和 `blog/` 目录。Cloudflare 部署使用 `public/` 中的镜像文件，因此每次内容变更都必须同步到对应的 `public/` 文件后再提交。
- `sitemap.xml` 和 `public/sitemap.xml` 必须反映当前公开 URL 结构。重要页面内容变更后，要同步更新对应 URL 的 `lastmod`。
- 博客编写要尽可能多使用图例、例子和分步骤说明。不要假设读者已经理解 KyteStore 的技术名词，应该先用通用存储概念解释，再引入 KyteStore 的具体设计。
- 博客的目的是向客户展示 KyteStore 的技术先进性、架构取舍和方案合理性。
- 博客应尽可能引用或对比社区与知名厂商的公开方案选型，包括但不限于 Ceph、Weka、VAST、Alluxio、JuiceFS、Jindo、MinIO、SeaweedFS、FoundationDB 等。
- 涉及竞品或社区方案时，优先使用官方文档、论文、设计文档、工程博客等一手资料，避免没有来源支撑的判断。
