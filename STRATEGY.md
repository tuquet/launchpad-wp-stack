# 🗺️ Chiến lược Phát triển & Mở rộng WordPress

Tài liệu này trình bày chiến lược phát triển WordPress **có khả năng mở rộng (Scalable)** từ giai đoạn MVP đến Enterprise, được thiết kế để tích hợp liền mạch với hệ sinh thái **LaunchPad**.

---

## 📐 Tổng quan Kiến trúc Hiện tại

Kiến trúc ban đầu được thiết kế theo mô hình **Single-Node Docker**, tối ưu cho giai đoạn phát triển và triển khai nhanh trên 1 VPS duy nhất.

```mermaid
graph TB
    subgraph HOST["🖥️ VPS / Máy Local"]
        subgraph DOCKER["Docker Network (wp-network)"]
            WP["🌐 WordPress<br/>(Apache + PHP)"]
            DB["🗄️ MariaDB 10.11"]
            CLI["🛠️ WP-CLI<br/>(Sidecar, on-demand)"]
        end

        subgraph VOLUMES["💾 Docker Named Volumes"]
            V1["wp-core"]
            V2["wp-uploads"]
            V3["db-data"]
        end

        subgraph BIND["📂 Bind Mounts (Dev Code)"]
            T["src/wp-content/themes/"]
            P["src/wp-content/plugins/"]
            M["src/wp-content/mu-plugins/"]
            PHP["config/php/uploads.ini"]
        end
    end

    USER["👤 Người dùng"] -->|":8080"| WP
    WP -->|"TCP :3306"| DB
    CLI -.->|"Shared Volume"| WP

    WP --- V1 & V2
    DB --- V3
    WP --- T & P & M & PHP

    style HOST fill:#1a1a2e,stroke:#16213e,color:#e0e0e0
    style DOCKER fill:#16213e,stroke:#0f3460,color:#e0e0e0
    style VOLUMES fill:#0f3460,stroke:#533483,color:#e0e0e0
    style BIND fill:#533483,stroke:#e94560,color:#e0e0e0
```

---

## 🛤️ Lộ trình Phát triển theo Giai đoạn

```mermaid
timeline
    title Lộ trình Scale WordPress — Từ MVP đến Enterprise
    section Giai đoạn 1 — MVP
        Single VPS : Docker Compose
                   : WordPress + MariaDB
                   : WP-CLI Sidecar
                   : Bind mount themes/plugins
    section Giai đoạn 2 — Growth
        Nginx Reverse Proxy : SSL/HTTPS (Let's Encrypt)
                            : Redis Object Cache
                            : Offload Media → S3/MinIO
                            : Automated Backup (cron)
    section Giai đoạn 3 — Scale
        Read Replica DB : MariaDB Master-Slave
                        : CDN (Cloudflare/BunnyCDN)
                        : Horizontal WP Instances
                        : Load Balancer
    section Giai đoạn 4 — Enterprise
        Kubernetes / Swarm : Auto-scaling Pods
                           : Headless WordPress (REST/GraphQL)
                           : CI/CD Pipeline (GitHub Actions)
                           : Monitoring Stack
```

---

## 🏗️ Giai đoạn 1 — MVP (Hiện tại)

> **Mục tiêu:** Lên sản phẩm nhanh, chi phí tối thiểu, nền tảng vững chắc cho tương lai.

### Thành phần hiện có

| Service | Image | Vai trò |
|---|---|---|
| `wordpress` | `wordpress:latest` | Web server (Apache + PHP) |
| `wp-db` | `mariadb:10.11` | Database server |
| `wpcli` | `wordpress:cli` | CLI administration (on-demand) |

### Quy trình Dev Workflow hiện tại

```mermaid
flowchart LR
    DEV["👨‍💻 Developer"] -->|"Code trên Host"| SRC["src/wp-content/<br/>themes · plugins · mu-plugins"]
    SRC -->|"Bind Mount<br/>(real-time sync)"| WP["🐳 WordPress Container"]
    WP -->|"Kết nối nội bộ"| DB["🐳 MariaDB Container"]

    DEV -->|"WP-CLI"| CLI["🐳 WP-CLI Container"]
    CLI -->|"Shared Volume"| WP

    WP -->|":8080"| BROWSER["🌐 Browser<br/>localhost:8080"]

    style DEV fill:#e94560,stroke:#1a1a2e,color:#fff
    style BROWSER fill:#533483,stroke:#1a1a2e,color:#fff
```

### ✅ Checklist MVP

- [x] Docker Compose với healthcheck
- [x] Auto-generate passwords & WP Salts
- [x] Bind mount themes/plugins/mu-plugins
- [x] Custom PHP config (upload 256MB, memory 512MB)
- [x] WP-CLI sidecar
- [x] One-click install script
- [ ] Triển khai lên VPS Production

---

## 🚀 Giai đoạn 2 — Growth (Tối ưu & Bảo mật)

> **Mục tiêu:** Cải thiện hiệu năng, bảo mật HTTPS, và tự động hóa backup.

### Kiến trúc mục tiêu

```mermaid
graph TB
    subgraph INTERNET["☁️ Internet"]
        USER["👤 Người dùng"]
        CDN["🌍 Cloudflare<br/>(DNS + DDoS Protection)"]
    end

    subgraph VPS["🖥️ VPS Production"]
        subgraph PROXY["Nginx Reverse Proxy"]
            NGX["Nginx + SSL<br/>(Let's Encrypt)"]
        end

        subgraph APP["Application Layer"]
            WP["🌐 WordPress<br/>(Apache + PHP)"]
            REDIS["⚡ Redis<br/>(Object Cache)"]
        end

        subgraph DATA["Data Layer"]
            DB["🗄️ MariaDB"]
            S3["📦 MinIO / S3<br/>(Media Storage)"]
        end

        subgraph OPS["Operations"]
            CRON["⏰ Backup Cron<br/>(DB + Files)"]
        end
    end

    USER --> CDN --> NGX
    NGX -->|"Proxy Pass"| WP
    WP -->|"Object Cache"| REDIS
    WP -->|"Query"| DB
    WP -->|"Media Upload"| S3
    CRON -.->|"mysqldump"| DB
    CRON -.->|"rsync"| S3

    style INTERNET fill:#0d1117,stroke:#30363d,color:#e0e0e0
    style VPS fill:#161b22,stroke:#30363d,color:#e0e0e0
    style PROXY fill:#1f6feb,stroke:#58a6ff,color:#fff
    style APP fill:#238636,stroke:#3fb950,color:#fff
    style DATA fill:#8b5cf6,stroke:#a78bfa,color:#fff
    style OPS fill:#d29922,stroke:#e3b341,color:#000
```

### Thành phần mới cần bổ sung

| # | Thành phần | Mục đích | Ưu tiên |
|---|---|---|---|
| 1 | **Nginx Reverse Proxy** | SSL termination, gzip, security headers | 🔴 Cao |
| 2 | **Redis Object Cache** | Cache database queries, giảm tải MariaDB 40-60% | 🔴 Cao |
| 3 | **MinIO / S3 Offload** | Tách media ra khỏi server, giảm disk I/O | 🟡 Trung bình |
| 4 | **Automated Backup** | Backup DB + files tự động hàng ngày | 🔴 Cao |
| 5 | **Fail2Ban** | Chống brute-force wp-login.php | 🟡 Trung bình |

### Compose mở rộng cho Growth

```yaml
# compose.growth.yml (extend từ compose.yml)
services:
  # ── Nginx Reverse Proxy + SSL ──
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./config/nginx/ssl:/etc/nginx/ssl
    depends_on:
      wordpress:
        condition: service_healthy

  # ── Redis Object Cache ──
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --maxmemory 128mb --maxmemory-policy allkeys-lru
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s

  # WordPress cần thêm biến môi trường cho Redis
  wordpress:
    environment:
      WP_REDIS_HOST: redis
      WP_REDIS_PORT: 6379
    depends_on:
      redis:
        condition: service_healthy

volumes:
  redis-data:
```

### Tích hợp với LaunchPad Registry Stack

```mermaid
sequenceDiagram
    participant USER as 👤 Người dùng
    participant NGINX_UI as 🔧 Nginx UI<br/>(Registry Stack)
    participant NGINX as 🌐 Nginx Proxy<br/>(WP Stack - Port 8080)
    participant WP as 📰 WordPress

    USER->>NGINX_UI: Truy cập domain<br/>(wp.yourdomain.com)
    NGINX_UI->>NGINX_UI: SSL Termination<br/>(Let's Encrypt)
    NGINX_UI->>NGINX: Proxy Pass → :8080
    NGINX->>WP: Forward Request
    WP-->>USER: Response (HTML)

    Note over NGINX_UI,NGINX: Nginx UI quản lý SSL & Domain<br/>WP Stack chỉ expose port 8080
```

---

## 📈 Giai đoạn 3 — Scale (Mở rộng hạ tầng)

> **Mục tiêu:** Xử lý lưu lượng truy cập lớn, đảm bảo high availability.

### Kiến trúc Horizontal Scaling

```mermaid
graph TB
    subgraph EDGE["☁️ Edge Layer"]
        CDN["🌍 CDN<br/>(Cloudflare / BunnyCDN)"]
        LB["⚖️ Load Balancer<br/>(HAProxy / Nginx)"]
    end

    subgraph APP_CLUSTER["📦 Application Cluster"]
        WP1["🌐 WordPress #1"]
        WP2["🌐 WordPress #2"]
        WP3["🌐 WordPress #3"]
        REDIS["⚡ Redis Cluster"]
    end

    subgraph DB_CLUSTER["🗄️ Database Cluster"]
        MASTER["MariaDB Master<br/>(Read + Write)"]
        SLAVE1["MariaDB Slave #1<br/>(Read Only)"]
        SLAVE2["MariaDB Slave #2<br/>(Read Only)"]
    end

    subgraph STORAGE["💾 Shared Storage"]
        S3["📦 S3 / MinIO<br/>(Media Files)"]
        NFS["📂 NFS / GlusterFS<br/>(wp-content shared)"]
    end

    CDN --> LB
    LB --> WP1 & WP2 & WP3
    WP1 & WP2 & WP3 --> REDIS
    WP1 & WP2 & WP3 -->|"Write"| MASTER
    WP1 & WP2 & WP3 -->|"Read"| SLAVE1 & SLAVE2
    MASTER -->|"Replication"| SLAVE1 & SLAVE2
    WP1 & WP2 & WP3 --> S3 & NFS

    style EDGE fill:#1f6feb,stroke:#58a6ff,color:#fff
    style APP_CLUSTER fill:#238636,stroke:#3fb950,color:#fff
    style DB_CLUSTER fill:#8b5cf6,stroke:#a78bfa,color:#fff
    style STORAGE fill:#d29922,stroke:#e3b341,color:#000
```

### Thách thức khi Scale WordPress & Giải pháp

| Thách thức | Vấn đề | Giải pháp |
|---|---|---|
| **Session Sharing** | Mỗi WP instance có session riêng | Dùng Redis làm session handler |
| **File Uploads** | Media chỉ lưu trên 1 instance | S3/MinIO offload + CDN |
| **wp-content Sync** | Theme/Plugin cần giống nhau trên mọi node | NFS shared volume hoặc Git deploy |
| **Database Bottleneck** | Single DB chịu tải kém | Master-Slave replication + read splitting |
| **Cache Invalidation** | Object cache không đồng bộ giữa nodes | Redis Cluster (centralized cache) |
| **Cron Jobs** | `wp-cron.php` chạy trên mọi instance | Disable WP-Cron, dùng system cron trên 1 node duy nhất |

### Cấu hình Read/Write Splitting

```mermaid
flowchart LR
    WP["WordPress"] -->|"INSERT / UPDATE / DELETE"| MASTER["MariaDB Master"]
    WP -->|"SELECT (Read)"| PROXY_SQL["ProxySQL<br/>(Query Router)"]
    PROXY_SQL --> SLAVE1["Slave #1"]
    PROXY_SQL --> SLAVE2["Slave #2"]
    MASTER -->|"Binlog Replication"| SLAVE1 & SLAVE2

    style MASTER fill:#e94560,stroke:#1a1a2e,color:#fff
    style SLAVE1 fill:#238636,stroke:#1a1a2e,color:#fff
    style SLAVE2 fill:#238636,stroke:#1a1a2e,color:#fff
    style PROXY_SQL fill:#d29922,stroke:#1a1a2e,color:#000
```

> [!TIP]
> Plugin **HyperDB** (do Automattic phát triển) hỗ trợ read/write splitting native cho WordPress mà không cần ProxySQL. Đặt file `db.php` vào `wp-content/` là đủ.

---

## 🏢 Giai đoạn 4 — Enterprise (Headless & CI/CD)

> **Mục tiêu:** Tách biệt Frontend/Backend, tự động hóa triển khai, monitoring toàn diện.

### Kiến trúc Headless WordPress

```mermaid
graph TB
    subgraph CLIENTS["📱 Client Applications"]
        WEB["🌐 Next.js / Nuxt<br/>(SSR Website)"]
        APP["📱 Mobile App<br/>(React Native)"]
        THIRD["🔌 Third-party<br/>(Integrations)"]
    end

    subgraph API_LAYER["🔗 API Gateway"]
        GW["Kong / Traefik<br/>(Rate Limit, Auth, Logging)"]
    end

    subgraph WP_BACKEND["📰 WordPress Backend (Headless)"]
        WP["WordPress<br/>(REST API / WPGraphQL)"]
        REDIS["⚡ Redis Cache"]
        DB["🗄️ MariaDB Cluster"]
        S3["📦 S3 Media"]
    end

    subgraph CICD["⚙️ CI/CD Pipeline"]
        GH["GitHub Actions"]
        REG["🐳 Docker Registry<br/>(LaunchPad Registry Stack)"]
    end

    subgraph MONITOR["📊 Monitoring"]
        PROM["Prometheus"]
        GRAF["Grafana"]
        ALERT["Alertmanager"]
    end

    WEB & APP & THIRD --> GW
    GW --> WP
    WP --> REDIS & DB & S3

    GH -->|"Build & Push"| REG
    REG -->|"Pull & Deploy"| WP

    WP -.->|"Metrics"| PROM
    PROM --> GRAF
    PROM --> ALERT

    style CLIENTS fill:#1f6feb,stroke:#58a6ff,color:#fff
    style API_LAYER fill:#d29922,stroke:#e3b341,color:#000
    style WP_BACKEND fill:#238636,stroke:#3fb950,color:#fff
    style CICD fill:#8b5cf6,stroke:#a78bfa,color:#fff
    style MONITOR fill:#e94560,stroke:#ff6b6b,color:#fff
```

### CI/CD Pipeline với LaunchPad Registry Stack

```mermaid
sequenceDiagram
    participant DEV as 👨‍💻 Developer
    participant GH as ⚙️ GitHub Actions
    participant REG as 🐳 LaunchPad Registry
    participant VPS as 🖥️ VPS Production

    DEV->>GH: Push code (git push)
    GH->>GH: Run Tests & Lint
    GH->>GH: Build Custom WP Image<br/>(themes + plugins baked in)
    GH->>REG: docker push image:v2.1.0
    GH->>VPS: SSH → docker compose pull
    VPS->>REG: Pull new image
    VPS->>VPS: docker compose up -d<br/>(Zero-downtime restart)
    VPS-->>DEV: ✅ Deployment Success<br/>(Slack/Discord notification)

    Note over GH,VPS: Quy trình giống y hệt<br/>LaunchPad CMS Fullstack
```

### Custom WordPress Docker Image (Production)

Khi scale lên enterprise, theme/plugin **không nên bind mount** mà cần **bake vào Docker Image** để đảm bảo tính nhất quán:

```dockerfile
# Dockerfile.production
FROM wordpress:latest

# ── PHP Configuration ──
COPY config/php/uploads.ini /usr/local/etc/php/conf.d/uploads.ini

# ── Themes & Plugins (Baked-in) ──
COPY src/wp-content/themes/ /var/www/html/wp-content/themes/
COPY src/wp-content/plugins/ /var/www/html/wp-content/plugins/
COPY src/wp-content/mu-plugins/ /var/www/html/wp-content/mu-plugins/

# ── Security Hardening ──
RUN chown -R www-data:www-data /var/www/html/wp-content
```

---

## 🔐 Chiến lược Bảo mật theo Giai đoạn

```mermaid
graph LR
    subgraph PHASE1["🟢 Giai đoạn 1 — MVP"]
        S1["✅ WP Salts tự động sinh"]
        S2["✅ DB password ngẫu nhiên"]
        S3["✅ Docker network cô lập"]
    end

    subgraph PHASE2["🟡 Giai đoạn 2 — Growth"]
        S4["🔒 SSL / HTTPS"]
        S5["🔒 Fail2Ban (brute-force)"]
        S6["🔒 .htaccess hardening"]
        S7["🔒 Disable XML-RPC"]
        S8["🔒 DB port không expose ra ngoài"]
    end

    subgraph PHASE3["🔴 Giai đoạn 3 — Scale"]
        S9["🛡️ WAF (ModSecurity)"]
        S10["🛡️ DDoS Protection (CF)"]
        S11["🛡️ IP Whitelist cho wp-admin"]
    end

    subgraph PHASE4["⚫ Giai đoạn 4 — Enterprise"]
        S12["🔐 API Gateway + JWT"]
        S13["🔐 RBAC (Role-Based Access)"]
        S14["🔐 Audit Logging"]
        S15["🔐 Vulnerability Scanning"]
    end

    PHASE1 --> PHASE2 --> PHASE3 --> PHASE4

    style PHASE1 fill:#238636,stroke:#3fb950,color:#fff
    style PHASE2 fill:#d29922,stroke:#e3b341,color:#000
    style PHASE3 fill:#e94560,stroke:#ff6b6b,color:#fff
    style PHASE4 fill:#1a1a2e,stroke:#533483,color:#e0e0e0
```

---

## 📦 Chiến lược Backup & Disaster Recovery

```mermaid
flowchart TB
    subgraph DAILY["⏰ Hàng ngày (Automated)"]
        B1["mysqldump → .sql.gz"]
        B2["wp-content/uploads → tar.gz"]
    end

    subgraph WEEKLY["📅 Hàng tuần"]
        B3["Full Volume Snapshot"]
    end

    subgraph STORAGE_TIER["💾 Lưu trữ Backup"]
        LOCAL["📂 Local<br/>(7 ngày gần nhất)"]
        S3_BACKUP["☁️ S3 / B2 Cloud<br/>(30 ngày)"]
        COLD["🧊 Glacier / Archive<br/>(1 năm)"]
    end

    DAILY --> LOCAL
    LOCAL -->|"Upload hàng đêm"| S3_BACKUP
    WEEKLY --> S3_BACKUP
    S3_BACKUP -->|"Lifecycle Policy"| COLD

    style DAILY fill:#238636,stroke:#3fb950,color:#fff
    style WEEKLY fill:#1f6feb,stroke:#58a6ff,color:#fff
    style STORAGE_TIER fill:#8b5cf6,stroke:#a78bfa,color:#fff
```

### Lệnh Backup thủ công (WP-CLI)

```bash
# Backup Database
docker compose run --rm wpcli wp db export /var/www/html/backup-$(date +%Y%m%d).sql

# Backup toàn bộ wp-content
docker compose run --rm wpcli tar -czf /var/www/html/wp-content-backup.tar.gz /var/www/html/wp-content/
```

---

## 📊 Monitoring & Observability (Giai đoạn 3+)

```mermaid
graph TB
    subgraph COLLECT["📡 Thu thập dữ liệu"]
        WP_METRICS["WordPress<br/>(Query Monitor Plugin)"]
        CADVISOR["cAdvisor<br/>(Container Metrics)"]
        NODE_EXP["Node Exporter<br/>(Host Metrics)"]
        MYSQL_EXP["MySQL Exporter<br/>(DB Metrics)"]
    end

    subgraph PROCESS["⚙️ Xử lý"]
        PROM["Prometheus<br/>(Time-series DB)"]
        LOKI["Loki<br/>(Log Aggregation)"]
    end

    subgraph VISUALIZE["📊 Hiển thị"]
        GRAFANA["Grafana Dashboard"]
    end

    subgraph ALERT["🚨 Cảnh báo"]
        ALERTM["Alertmanager"]
        SLACK["Slack / Discord"]
        EMAIL["Email"]
    end

    WP_METRICS & CADVISOR & NODE_EXP & MYSQL_EXP --> PROM
    PROM --> GRAFANA
    LOKI --> GRAFANA
    PROM --> ALERTM
    ALERTM --> SLACK & EMAIL

    style COLLECT fill:#1f6feb,stroke:#58a6ff,color:#fff
    style PROCESS fill:#238636,stroke:#3fb950,color:#fff
    style VISUALIZE fill:#8b5cf6,stroke:#a78bfa,color:#fff
    style ALERT fill:#e94560,stroke:#ff6b6b,color:#fff
```

### Các Metrics cần theo dõi

| Metric | Cảnh báo khi | Hành động |
|---|---|---|
| CPU Usage | > 80% trong 5 phút | Scale thêm WP instance |
| Memory Usage | > 85% | Tăng PHP `memory_limit` hoặc thêm RAM |
| DB Connections | > 100 concurrent | Bật connection pooling / thêm read replica |
| Response Time (P95) | > 2 giây | Kiểm tra slow queries, bật Redis cache |
| Disk Usage | > 80% | Offload media sang S3, chạy `cleanup.sh` |
| Error Rate (5xx) | > 1% | Kiểm tra logs, rollback nếu cần |

---

## 🔄 So sánh Kiến trúc theo Giai đoạn

| Tiêu chí | MVP | Growth | Scale | Enterprise |
|---|---|---|---|---|
| **Số server** | 1 VPS | 1 VPS | 2-5 VPS | Kubernetes Cluster |
| **Database** | Single MariaDB | Single + Backup | Master-Slave | Galera Cluster |
| **Cache** | Không | Redis Object Cache | Redis Cluster | Redis Sentinel |
| **Media** | Docker Volume | Docker Volume | S3/MinIO | S3 + CDN |
| **SSL** | Không | Let's Encrypt | Let's Encrypt | Wildcard SSL |
| **CI/CD** | Manual | Script | GitHub Actions | Full Pipeline |
| **Monitoring** | `docker logs` | Query Monitor | Prometheus + Grafana | Full Stack |
| **Backup** | Manual | Cron daily | Cron + S3 | Multi-region |
| **Traffic** | ~1K/ngày | ~10K/ngày | ~100K/ngày | ~1M+/ngày |
| **Chi phí/tháng** | ~$5-10 | ~$15-30 | ~$100-300 | ~$500+ |

---

## 🌌 Tích hợp Hệ sinh thái LaunchPad

```mermaid
graph TB
    subgraph ECOSYSTEM["🌌 LaunchPad Ecosystem"]
        CMS["💻 LaunchPad CMS Fullstack<br/>(Strapi 5 + Next.js 16)"]
        WP["📰 LaunchPad WordPress Stack<br/>(WordPress + MariaDB)"]
        REG["🐳 LaunchPad Registry Stack<br/>(Docker Registry + Nginx UI)"]
    end

    subgraph SHARED["🔗 Chia sẻ Hạ tầng"]
        NGINX_UI["🔧 Nginx UI<br/>(SSL + Domain Proxy)"]
        REGISTRY["📦 Private Docker Registry"]
    end

    CMS -->|"Proxy qua :8000"| NGINX_UI
    WP -->|"Proxy qua :8080"| NGINX_UI
    CMS -->|"Push/Pull Images"| REGISTRY
    WP -->|"Push/Pull Images"| REGISTRY
    REG --- NGINX_UI & REGISTRY

    style ECOSYSTEM fill:#1a1a2e,stroke:#533483,color:#e0e0e0
    style SHARED fill:#0f3460,stroke:#1f6feb,color:#e0e0e0
```

> [!IMPORTANT]
> Tất cả các stack trong hệ sinh thái LaunchPad đều chia sẻ chung các quy ước:
> - **Script pattern:** `copy-env.sh` (sinh secrets), `install.sh` (one-click), `reset.sh`, `cleanup.sh`
> - **Secret pattern:** Placeholder `tobemodified_*` → auto-replace bằng `openssl rand`
> - **Compose pattern:** `compose.yml` (dev) + `compose.prod.yml` (production)
> - **Deploy pattern:** Build Local → Push Registry → Pull VPS → Zero-downtime restart

---

## 📌 Hành động tiếp theo (Next Steps)

Dựa trên lộ trình phía trên, những việc ưu tiên cao nhất để chuyển từ MVP → Growth:

1. **Tạo `compose.prod.yml`** — Nginx reverse proxy + SSL + không expose DB port
2. **Thêm Redis** — Cài plugin [Redis Object Cache](https://wordpress.org/plugins/redis-cache/) + thêm service Redis vào compose
3. **Viết Backup Script** — `scripts/backup.sh` + cron job hàng đêm
4. **Security Hardening** — Disable XML-RPC, limit login attempts, `.htaccess` rules
5. **Tích hợp LaunchPad Registry Stack** — Nginx UI quản lý SSL/Domain cho WordPress
