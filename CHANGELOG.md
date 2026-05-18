# HicOS Changelog

## Current Snapshot

- `.hl` 文件：`454`（76 根目录 + 385 内核模块）
- H-L 总行数：`~153,000`
- 内核模块：`385`
- Shell 命令：`1513`
- 最近完成功能迭代：`399`（pooling + rnn + lstm）
- 当前阶段：第五阶段·ML深化（Phase 5）
- **Milestone M3 已达成**（iter 385，完整存储引擎）

## Iteration 399 — lstm.hl：LSTM 门控循环单元

- **`lstm.hl`**（Buffer: 0x1C60000）：LM_INPUT=4，LM_HIDDEN=4，LM_SCALE=256
  - 四门：i（输入门）/ f（遗忘门）/ o（输出门）/ g（细胞门）
  - `sigmoid_fp(x) = clamp(x/2 + SCALE/2, 0, SCALE)`；`tanh_fp(x) = clamp(x, -SCALE, SCALE)`
  - `lstm_step()`：计算所有门控值 → 更新细胞状态 c_t → 更新隐状态 h_t
  - 权重矩阵：lm_W_xi/xf/xo/xg（输入→门）+ lm_W_hi/hf/ho/hg（隐→门）
  - `lm_get_i_gate(j)` / `lm_get_f_gate(j)` 可读取门控值
  - 测试：W_xi/xg/xo=SCALE，x[0]=1.0 → i=256 f=128 c1=256 h1=256 → PASS

## Iteration 398 — rnn.hl：简单循环神经网络

- **`rnn.hl`**（Buffer: 0x1C50000）：RN_INPUT=4，RN_HIDDEN=4，RN_SCALE=256
  - `h_t = tanh(W_xh * x_t + W_hh * h_{t-1} + b)`
  - `_rn_tanh_fp(x)`：clamp(x, -256, 256)（线性区近似激活）
  - `rnn_step()`：用 rn_new_hidden 暂存避免原地更新读写冲突
  - 可选输出投影：`rn_W_hy[j]` × h[j] / scale → `rn_output`
  - 测试：W_xh[0][0]=128, W_hh[0][0]=128, x[0]=256 → h1=128 h2=192 h3=224 → PASS

## Iteration 397 — pooling.hl：2D 最大/平均池化

- **`pooling.hl`**（Buffer: 0x1C40000）：PL_MAX_CH=4，8×8 网格
  - 输入布局与 conv2d 相同：`pl_input[ch*64 + r*8 + c]`
  - `pool_max_forward(in_ch, pool_size, stride)`：滑动窗口取最大值
  - `pool_avg_forward(in_ch, pool_size, stride)`：滑动窗口整除平均
  - 输出尺寸：`h_out = (PL_MAX_H - pool_size) / stride + 1`
  - 测试：4×4 输入(1..16)，2×2 stride=2 → max(0,0)=6 max(0,1)=8 max(1,0)=14 max(1,1)=16；avg(0,0)=3 avg(0,1)=5 → PASS

## Iteration 396 — conv2d.hl：2D 卷积层（Phase 5 ML深化开始）

- **`conv2d.hl`**（Buffer: 0x1C30000）：CV_MAX_H/W=8，CV_MAX_CH=4，CV_SCALE=256
  - 固定点运算：所有权重/输入按 CV_SCALE=256 缩放，输出 `accum/256` 后 ReLU
  - 输入张量：`cv_input[ch*64 + r*8 + c]`（CV_MAX_CH×H×W flat array）
  - 卷积核：`cv_kernel[oc*36 + ic*9 + kr*3 + kc]`（out_ch×in_ch×kH×kW）
  - `conv2d_forward(in_ch, out_ch, k_size, stride, padding)` → 完整嵌套循环
  - `_cv_relu(x)`：x<0 返回 0；`_cv_pad_input`：边界外返回 0（零填充）
  - 测试：4×4 输入，中心权重=256 的恒等卷积，stride=1 padding=1 → v00=1 v12=7 v33=16 oh=8 → PASS

## Iteration 395 — websocket_compression.hl：WebSocket permessage-deflate（RFC 7692）

- **`websocket_compression.hl`**（Buffer: 0x1C20000）：WC_MAXCONNS=8，WC_WBITS=9（窗口512字节）
  - 每连接滑动窗口（flat: conn*512 + pos）+ 压缩上下文
  - `_wc_find_match(conn_id, data_hash, win_base)`：LZ77 模拟，散列碰撞检测，返回 `dist*256+len`
  - 匹配≥3字节：back-reference 编码 `comp_len = data_len/3 + 2`
  - 无匹配：Huffman 字面编码 `comp_len = data_len*7/8 + 1`（约 87% ratio）
  - `wc_ctx_takeover`：1=no_context_takeover，每帧后重置窗口
  - 测试：重复消息 cl2≤cl1；ratio0<100；frames0=2 → PASS

## Iteration 394 — grpc_stream.hl：gRPC 流式 RPC（HTTP/2 over H-L）

- **`grpc_stream.hl`**（Buffer: 0x1C10000）：GS_MAXSTREAMS=16，4 种流类型
  - 流类型：UNARY=0 / SERVER_STREAM=1 / CLIENT_STREAM=2 / BIDI=3
  - 状态机：IDLE→OPEN→HALF_CL→CLOSED / RESET
  - `_gs_lpm_encode(msg_hash)`：Length-Prefix Message 编码模拟
  - `gs_send(sid, msg)`：UNARY 自动生成 1 个响应；SERVER_STREAM 自动生成 3 个响应
  - `gs_recv(sid)`：队列出队，空返回 -1（O(n) 左移）
  - `gs_close(sid)`：写 trailer（status + method hash），转 CLOSED
  - 测试：UNARY r0>0 r0b=-1；SERVER 3消息 sr3=-1 pend=0；state=CLOSED → PASS

## Iteration 393 — prometheus.hl：Prometheus 指标采集与文本导出

- **`prometheus.hl`**（Buffer: 0x1C00000）：PM_MAXMETRICS=32，4 种类型
  - Counter / Gauge / Histogram / Summary（`pm_counter/pm_gauge/pm_histogram/pm_summary`）
  - 标签支持：每个指标最多 4 个 key_hash=val_hash 标签对（`pm_label`）
  - `pm_inc(id)` / `pm_add(id, delta)` / `pm_set(id, val)`：修改值
  - Histogram：8 固定桶（上界 1/5/10/50/100/500/1000/+Inf），累积计数 + sum + count
  - Summary：最多 64 个观测值，插入排序后用百分位索引（`pm_quantile(id, pct)`）
  - 测试：counter=3；gauge=32768；histogram sum=211 count=3 b0=0 b2=2；p50=500 p90=900 → PASS

## Iteration 392 — opentelemetry.hl：分布式追踪（W3C Trace Context）

- **`opentelemetry.hl`**（Buffer: 0x1BF0000）：OT_MAXSPANS=32，OT_MAXATTRS=8/span
  - Span 字段：trace_id / span_id / parent_span / name_hash / start_tick / end_tick / status
  - `otel_trace_new()`：创建新 Trace，返回 trace_idx
  - `otel_span_start(tid, parent, name)` → `otel_span_attr(slot, k, v)` → `otel_span_end(slot)`
  - Status：UNSET=0 / OK=1 / ERROR=2；`otel_span_set_status`
  - `otel_export()`：序列化已结束 span 到导出缓冲区（5字段/span：trace/id/parent/status/duration）
  - 测试：1 trace + 3 spans（root + db.query + cache.lookup(ERROR)）→ export=3，duration>0 → PASS

## Iteration 391 — torrent_proto.hl：BitTorrent 对等协议（BEP-3）

- **`torrent_proto.hl`**（Buffer: 0x1BE0000）：BT_MAXPEERS=16，BT_MAXPIECES=64
  - 消息类型：CHOKE/UNCHOKE/INTERESTED/NOT_INTERESTED/HAVE/BITFIELD/REQUEST/PIECE/CANCEL
  - `bt_handshake(peer_id)`：握手交换 + BITFIELD 协商，进入 ACTIVE 状态
  - `bt_recv_bitfield(peer_id, bitfield_hash)`：逐位解码对端拥有的分片，更新稀缺度计数器
  - `bt_select_rarest(peer_id)`：稀缺优先选取对端有、我方无的最稀缺分片
  - `bt_request_piece(peer_id, piece_idx)`：发送 REQUEST，模拟接收 PIECE 响应
  - `bt_download_progress()`：返回完成百分比×100（0–10000）
  - 测试：3 个对端各有不同分片组；下载 2 片；progress=2500；rarest≥4 → PASS

## Iteration 390 — dht.hl：Kademlia 分布式哈希表

- **`dht.hl`**（Buffer: 0x1BD0000）：DHT_MAXNODES=32，DHT_K=8，16-bit 键空间
  - XOR 距离度量：`_dht_xor(a,b)` 逐位算术模拟（无 XOR 运算符）
  - K-桶路由表：16 个桶，按最高有效位分级，每桶最多 K=8 节点
  - `_dht_bucket_for(dist)`：按最高位确定桶编号
  - `dht_add_node(id, addr)`：加入路由表，写入对应 K-桶
  - `dht_find_node(target)`：在路由表中找 k 个最近节点（距离排序）
  - `dht_store(key, val)` / `dht_lookup(key)`：本地键值存储（迭代 STORE 简化）
  - `dht_ping(node_id)`：检查节点是否在路由表中
  - 测试：10 节点入网；存储 key=42→421（覆盖）；lookup(42)=421；find_node 返回 >0 个结果 → PASS

## Iteration 389 — dns_over_https.hl：DoH 加密 DNS 客户端

- **`dns_over_https.hl`**（Buffer: 0x1BC0000）：DOH_MAXQ=16，DOH_CACHE=32
  - 记录类型：A=1 / CNAME=5 / MX=15 / TXT=16 / AAAA=28
  - `_doh_build_wire(qname_hash, qtype)`：构造 DNS 线格式查询（12 字节头 + QNAME + QTYPE/QCLASS）
  - `doh_query(domain_hash, type)`：先查 LRU 缓存；未命中则模拟 HTTPS POST，解析响应并缓存
  - `_doh_cache_lookup` / `_doh_cache_insert`：LRU 缓存（按 lru_clock 驱逐）
  - `doh_flush()` / `doh_tick()`：清空缓存 / TTL 递减+过期
  - 测试：相同查询走缓存（r1==r2）；不同域名不同结果；flush 后 cache_size=0；重查得相同值 → PASS

## Iteration 388 — http3_quic.hl：HTTP/3 over QUIC 传输

- **`http3_quic.hl`**（Buffer: 0x1BB0000）：H3_MAXCONNS=8，H3_MAXSTREAMS=16
  - QUIC 握手模拟：Initial→Handshake→1-RTT，`_h3_derive_key(cid, server)` 推导会话密钥
  - HTTP/3 帧类型：DATA=0 / HEADERS=1 / SETTINGS=4 / GOAWAY=7
  - `h3_connect(cid, server_hash)`：完成 QUIC 握手，进入 ESTAB 状态
  - `h3_get(cid, path_hash)`：分配新流，发送 HEADERS 帧（GET），返回 stream_idx
  - `h3_post(cid, path_hash, body_hash)`：发送 HEADERS+DATA 帧（POST）
  - `h3_recv_status / h3_recv_data`：读取流响应状态码和数据
  - `h3_close(cid)`：发送 GOAWAY 帧，状态置 CLOSED
  - 测试：connect→GET(path=1111)→d1=2222；POST(path=2222,body=3333)→d2=3334；close → PASS

## Iteration 387 — tls13.hl：TLS 1.3 握手状态机 + AEAD 记录层

- **`tls13.hl`**（Buffer: 0x1BA0000）：TLS13_MAX=8，状态 IDLE→CH_SENT→SH_RCVD→HS_DONE→ESTAB→ALERT
  - HKDF 模拟：`_tls_hkdf_expand(secret, label) = (secret*31 + label*7 + 1) mod 65521`
  - 密钥调度：early_secret → hs_secret → master_secret → client_key/server_key/client_iv/server_iv
  - `tls_client_hello(sid, rand, eph_priv)`：生成 epub，进入 CH_SENT
  - `tls_server_hello(sid, srand, s_eph_pub)`：DH 共享秘钥 → 密钥调度推导全套密钥
  - `tls_handshake_finish(sid)`：双向 Finished 确认，进入 ESTAB
  - AEAD 加密：`ct = (pt + client_key + seq) mod 65536`；解密：逆向恢复
  - 测试：完整握手 → state=ESTAB；send(9999) → 正确解密 → PASS

## Iteration 386 — wireguard.hl：WireGuard VPN 协议模拟

- **`wireguard.hl`**（Buffer: 0x1B90000）：WG_MAXPEERS=8，状态 IDLE/INIT_SENT/RESP_SENT/ESTABLISHED
  - Noise_IKpsk2 握手模拟：`_wg_derive_key(priv, pub, psk) = ((priv*pub mod P) + psk)*17 mod P`
  - `wg_handshake_init(id)`：生成临时密钥对，构造 INIT 消息
  - `wg_handshake_resp(id)`：响应方推导会话密钥，返回 RESP 消息
  - `wg_establish(id)`：发起方推导相同会话密钥，进入 ESTABLISHED
  - `wg_encrypt(id, pt)`：`ct = (pt + sk + ctr) mod 65536`，发送计数器递增
  - `wg_decrypt(id, ct, ctr)`：重放防护（拒绝旧 counter）+ 逆向解密
  - 测试：双方推导出相同 sk；encrypt(9999) + decrypt → pt=9999；重放 → -1 → PASS

## Iteration 385 — db_engine.hl：关系型数据库引擎（Milestone M3）

- **`db_engine.hl`**（Buffer: 0x1B80000）：DB_MAXTABLES=8，DB_MAXROWS=64，DB_MAXCOLS=8
  - 行存储：`db_rows[tid*512 + rid*8 + col]`（TBL_STRIDE=512，ROW_STRIDE=8）
  - `db_insert(tid, c0..c3)`：追加行，若已建索引则同步更新哈希索引条目
  - `db_select_eq(tid, col, val)`：col=0 且有索引 → 直接 `_db_idx_lookup(val)`（scan=1）；否则顺序扫全表
  - `db_select_range(tid, col, lo, hi)`：顺序扫描，统计 lo≤val≤hi 的行数
  - `db_create_index(tid)`：对已有行在 col-0 上构建哈希索引
  - `db_explain(tid, col, use_index)`：委托 `qp_scan + qp_proj + qp_explain`，返回总代价
  - 测试：8 行，col-0 索引；select_eq(col=0,5)→rid=4,scan=1；select_eq(col=1,30)→rid=2,scan=8；range[20,50]=4；update/verify → PASS
  - **Milestone M3 达成**：完整关系型存储引擎（B-Tree + B+Tree + LSM + WAL + MVCC + Transaction + HashIndex + BTreeIndex + QueryPlan + DBEngine）

## Iteration 384 — query_plan.hl：规则驱动查询计划生成

- **`query_plan.hl`**（Buffer: 0x1B70000）：QP_MAXNODES=32
  - 节点类型：SEQSCAN=1 / INDEXSCAN=2 / NESTLOOP=3 / HASHJOIN=4 / SORT=5 / AGG=6 / FILTER=7 / PROJ=8
  - 规则：`index_id≥0` → INDEXSCAN（cost=log2(n)×sel）；否则 SEQSCAN（cost=n）
  - JOIN 选择：两侧行数均>100 → HASHJOIN；否则 NESTLOOP
  - ORDER BY → SORT（cost+=n×log2(n)）；GROUP BY → AGG（cost+=n）
  - `qp_explain(root)`：打印全部节点 type/rows/cost
  - 测试：T1(1000行,有索引,sel=5) + T2(200行,无索引) → INDEXSCAN+SEQSCAN+NESTLOOP+SORT+AGG+PROJ → PASS

## Iteration 383 — index_btree.hl：B-Tree 索引层（多 RID + 区间扫描）

- **`index_btree.hl`**（Buffer: 0x1B60000）：IBT_MAXKEYS=64，IBT_MAXRIDS=4
  - 有序键数组（二分定位 + 插入右移），非唯一索引：同键最多 4 个 RID
  - `ibt_insert(k, rid)`：键已存在则追加 RID；新键则二分定位并移位插入
  - `ibt_range_scan(lo, hi)`：二分定位起点，线性扫描至 hi
  - 测试：插入 8 个键（key=1 两次）→ range[2,5]=4；key1 有 2 个 RID → PASS

## Iteration 382 — index_hash.hl：哈希索引（链式冲突解决）

- **`index_hash.hl`**（Buffer: 0x1B50000）：IH_BUCKETS=64，IH_MAXENT=256
  - 桶数组 + 条目池链表；`_ih_hash(k) = k - (k/64)*64`（无 %）
  - `ih_insert(k, rid)`：链中已有则更新；否则头插法追加
  - `ih_delete(k)`：链表解链，条目标记为空闲
  - `ih_load_factor()`：size×100 / buckets
  - 测试：插入 10 项 → lookup 正确；删除 key=14 后 miss → size=9 → PASS

## Iteration 381 — transaction.hl：ACID 事务 API

- **`transaction.hl`**（Buffer: 0x1B40000）：TX_MAX=16，TX_WB_MAX=128
  - `tx_begin()`：分配槽位，调用 `mvcc_begin_tx` 获取快照时间戳，WAL 写 BEGIN
  - `tx_write(slot, k, v)`：写缓冲暂存 + WAL WRITE；延迟应用至 MVCC
  - `tx_read(slot, k)`：快照隔离读（委托 `mvcc_read(k, snap_ts)`）
  - `tx_commit(slot)`：写写冲突检测（乐观并发）→ 分配 commit_ts → 批量 `mvcc_write` → WAL COMMIT
  - `tx_abort(slot)`：WAL ABORT，丢弃写缓冲
  - 测试：txnA 写 k=1,2 提交；txnB 读到 100，写 k=1=101 提交；txnC 读到 101 → PASS

## Iteration 380 — mvcc.hl：多版本并发控制

- **`mvcc.hl`**（Buffer: 0x1B30000）：MV_MAXVER=64
  - 版本字段：(key, val, xmin, xmax, live)；xmax=0 表示版本仍活跃
  - `mvcc_write(k, v, ts)`：关闭同 key 旧版本（设 xmax=ts），插入新版本（xmin=ts, xmax=0）
  - `mvcc_read(k, snap_ts)`：可见条件 `xmin≤snap_ts AND (xmax==0 OR xmax>snap_ts)`，取最大 xmin
  - `mvcc_vacuum(horizon)`：清除 xmax≤horizon 的版本（dead tuple）
  - 测试：ts=1 写 k=5→50, ts=2 写 k=5→55；read(5,1)=50, read(5,2)=55；vacuum 回收 1 条 → PASS

## Iteration 379 — wal.hl：预写日志

- **`wal.hl`**（Buffer: 0x1B20000）：WAL_MAXRECS=64，LSN 从 1 单调递增
  - 记录字段：(lsn, type, txid, key, val, checksum)；checksum = sum mod 65536
  - 支持记录类型：BEGIN / WRITE / COMMIT / ABORT / CHECKPOINT
  - `wal_replay(from_lsn)`：两遍扫描——第一遍收集已提交 txid，第二遍 redo 其 WRITE
  - `wal_verify(idx)`：校验 checksum，保障日志完整性
  - 测试：txn1(提交) + txn2(abort) + txn3(提交) → replay=3 条（排除 abort） → PASS

## Iteration 378 — lsm_memtable.hl：LSM MemTable 排序写缓冲

- **`lsm_memtable.hl`**（Buffer: 0x1B10000）：LSM_MAXKEYS=64
  - `lsm_put(k,v)`：二分定位插入保持有序，同键更新序号最大者胜
  - `lsm_get(k)`：二分查找 O(log n)
  - `lsm_flush()`：冻结 MemTable，追加至 SSTable 数组（已有序）
  - `lsm_ss_get(k)`：在不可变 SSTable 中二分查找
  - `lsm_compact(a,b,...)`：归并两个有序 run，序列号冲突取大者
  - 测试：6 次写入（含一次覆盖）→ flush=5；ssget=200；compacted≥5 → PASS

## Iteration 377 — btree_plus.hl：B+ 树（区间查询）

- **`btree_plus.hl`**（Buffer: 0x1B00000）：BTP_T=2，BTP_MAXNODES=64
  - 与 B-Tree 的核心区别：所有 (k,v) 只存于叶节点，内部节点仅做路由
  - 叶节点通过 `btp_next[]` 链表连接，支持顺序遍历
  - `_btp_split_leaf`：叶分裂时更新链表指针，推 copy 键至父节点
  - `_btp_split_internal`：内部节点分裂，推 median 至父节点（不保留）
  - `btp_range(lo, hi)`：沿叶链表收集 [lo,hi] 范围内所有键值对
  - 测试：插入 1..10 → range[3,7]=5 项；point search 正确 → PASS

## Iteration 376 — btree.hl：B-Tree（读优化键值存储）

- **`btree.hl`**（Buffer: 0x1AF0000）：BT_T=2，BT_MAXNODES=64（2-3-4 树）
  - `bt_insert(k,v)`：分裂下行（split-on-the-way-down），根满时升高树
  - `bt_search(nd, k)`：递归二分定位，O(log_T N)
  - `_bt_split_child(par, ci)`：CLRS 标准分裂——中位键升至父节点
  - `bt_height()`：沿最左子路径计算树高
  - 测试：插入 1..12 → search(5)=50，search(12)=120，miss=-1 → PASS

## Iteration 375 — jit_stub.hl：JIT 编译桩

- **`jit_stub.hl`**（Buffer: 0x1AE0000）：JIT_MAXFUNCS=32，JIT_THRESHOLD=10
  - `jit_register(fid)` + `jit_call(fid)`：调用计数热点检测，超过阈值即标记为 hot
  - `jit_compile_const(slot, retval)`：生成常量返回桩（prologue + mov eax,imm32 + epilogue）
  - `jit_compile_add(slot, base, add)`：生成加法桩（mov eax + add rax,imm32 + epilogue）
  - `_jit_emit_prologue/epilogue`：x86_64 标准帧（push rbp; mov rbp,rsp / pop rbp; ret）
  - 测试：f1 调用 15 次（hot），f2 调用 5 次（cold）；编译 2 个桩；bytes>8；hits 正确 → PASS

## Iteration 374 — perf_counter.hl：PMU 性能计数器

- **`perf_counter.hl`**（Buffer: 0x1AD0000）：PC_MAXCOUNTERS=8，PC_MAXSAMPLES=64
  - PMU 事件码：INST=0xc0，LLC_MISS=0x412e，BR_MISS=0xc5，CYCLES=0x3c
  - `pc_add_counter(evt,umask)` + `pc_snapshot()`：读取增量，处理 48 位计数器回绕
  - `pc_ipc()`：IPC×100；`pc_llc_miss_rate/pc_br_miss_rate()`：每千指令缺失率
  - `pc_sample(id, ip)`：NMI 样本环形缓冲区（64 槽）
  - 测试：1M inst / 500K cyc / 5K LLC / 2.5K BR → IPC*100=200，LLC/1000=5，samples=2 → PASS

## Iteration 373 — dwarf.hl：DWARF 调试信息生成

- **`dwarf.hl`**（Buffer: 0x1AC0000）：DWARF_MAXLINES=64，DWARF_MAXVARS=32
  - 行号状态机：addr/file/line/col/is_stmt；标准操作码 DW_LNS_COPY/ADVANCE_PC/ADVANCE_LINE 等
  - `dw_add_file(name,dir)` + `dw_add_line(addr,file,line,col,stmt)`：构建行号表
  - `dw_add_var(name,type,loc,offset,func)`：变量位置信息（DW_OP_fbreg/reg）
  - `dw_emit_line_table()`：输出 .debug_line 节字节流（含 ULEB128/SLEB128 编码）
  - 末尾 DW_LNE_end_sequence（扩展操作码）正确终止行号程序
  - 测试：3 条行表项 + 2 个变量，输出字节数 >20 → PASS

## Iteration 372 — dynamic_linker.hl：PLT/GOT 动态链接

- **`dynamic_linker.hl`**（Buffer: 0x1AB0000）：DL_MAXSYMS=32，DL_MAXLIBS=8
  - `dl_add_library(name,base)` + `dl_add_import(sym,lib)`：注册共享库与导入符号
  - GOT slot = `GOT_BASE + (3+id)*8`；PLT stub = `PLT_BASE + (id+1)*16`（前 3 个 GOT 项保留）
  - `dl_resolve(sym,offset)`：懒绑定模拟——lib_base + offset 写入 GOT
  - `dl_resolve_all()`：批量解析所有未解决符号
  - 测试：libc.so 导入 printf/malloc/free → 全解析，地址 = 0x7f000100/200/300 → PASS

## Iteration 371 — linker_ar.hl：静态归档增量链接

- **`linker_ar.hl`**（Buffer: 0x1AA0000）：AR_MAXMEMBERS=16，AR_MAXSYMS=64
  - `ar_add_member(name,size)` / `ar_add_symbol(sym,member)`：构建归档符号索引
  - `ar_add_undef(sym)` / `ar_link()`：增量链接——仅选取满足 undef 引用的成员，迭代至不动点
  - `ar_total_size()`：被选成员字节总量
  - 测试：3 个成员，undef sqrt+strlen → 选中 m0+m1，总大小 192 字节 → PASS

## Iteration 370 — linker_elf.hl：ELF64 输出布局

- **`linker_elf.hl`**（Buffer: 0x1A90000）：ELF_MAXSECTS=8，ELF_MAXSYMS=32，ELF_MAXRELS=32
  - `elf_set_section_size(text,data,bss)` / `elf_layout()`：计算各节文件偏移与虚拟地址
  - 节序：.text → .data → .bss(nobits) → .symtab → .rela.text → section header table
  - `elf_add_symbol(name,value,size,bind,type,sect)`：添加符号表条目
  - `elf_add_rela(offset,sym,type,addend)`：添加重定位条目
  - 测试：text=256 data=64 bss=128，entry=0x400040，file_size>256 → PASS

## Iteration 369 — generics.hl：泛型单态化展开

- **`generics.hl`**（Buffer: 0x1A80000）：GN_MAXTEMPL=16，GN_MAXINST=32
  - `gn_begin_template(name, nparams)` + `gn_add_op(tmpl, kind, f0, f1, f2)`：定义泛型模板
  - 类型参数编码：`GN_TPARAM+k`（k 为参数索引，具体类型 0=Int/1=Bool/2=Float）
  - `gn_instantiate(tmpl, t0..t3)`：展开模板；`_gn_subst_type` 替换类型参数
  - 每次实例化生成独立 op 序列（`gn_iop_*`），存储替换后的类型注解
  - 测试：`identity<T>` 实例化为 `<Int>` 和 `<Bool>`，op 类型分别正确替换 → PASS

## Iteration 368 — type_checker.hl：类型检查器（诊断报告）

- **`type_checker.hl`**（Buffer: 0x1A70000）：TC_MAXNODES=32，TC_MAXERRS=8
  - 类型标签：Int=0，Bool=1，Str=2，Float=3，Unknown=4，Error=5
  - 检查规则：算术运算需 Int，逻辑运算需 Bool，等价比较需相同类型，ret 需匹配声明返回类型
  - `tc_run()`：逐语句检查，收集错误至 `tc_err_node/exp/got`
  - 测试：`z=x+x`（ok）; `w=y&&z`（z 为 Int 非 Bool → 错）; `ret z`（Int 非 Bool → 错）→ 2 错误 → PASS

## Iteration 367 — type_infer.hl：Hindley-Milner 类型推断

- **`type_infer.hl`**（Buffer: 0x1A60000）：TI_MAXNODES=32，TI_MAXTVARS=32
  - 类型编码：Int=0，Bool=1，TVar(v)=200+v，Fun(a,r)=300+id
  - `_ti_unify(s,t)`：union-find 合一；含出现检查（occur check）防止无限类型
  - `_ti_infer(node)`：Algorithm W 核心递归；Var/Lam/App/Lit 四种节点
  - `ti_run(root)`：从根推断，返回最终类型（经 `_ti_resolve` 展开）
  - 测试：`(\x.42) 42` → 应用类型 = Int → PASS

## Iteration 366 — calling_conv.hl：System V AMD64 调用约定

- **`calling_conv.hl`**（Buffer: 0x1A50000）：完整 System V AMD64 ABI 建模
  - 整数参数寄存器：RDI RSI RDX RCX R8 R9（前 6），其余压栈
  - 浮点参数寄存器：XMM0-XMM7（前 8），其余压栈
  - `cc_compute_frame(locals, n_callee)`：帧大小 16 字节对齐（含返回地址）
  - `cc_is_callee_saved(r)` / `cc_is_caller_saved(r)`：寄存器保存分类查询
  - 测试：8 个整数参数，前 6 在寄存器，后 2 在栈；帧 32+16+8=56→64 → PASS

## Iteration 365 — regalloc_coalesce.hl：寄存器合并（Briggs + George）

- **`regalloc_coalesce.hl`**（Buffer: 0x1A40000）：RC_MAXVARS=32，K=8 颜色
  - `rc_add_interfere(u,v)` / `rc_add_copy(u,v)`：构建干涉图 + 复制提示
  - `_rc_briggs_ok(u,v)`：合并结果高度节点数 < K 则安全
  - `_rc_george_ok(u,v)`：v 的每个高度邻居也干涉 u 则安全
  - Union-Find 维护合并集合；后续图着色复用合并代表的颜色
  - 测试：4 个变量，2 对复制无干涉 → 合并 ≥1 → PASS

## Iteration 364 — regalloc_linear_scan.hl：线性扫描寄存器分配

- **`regalloc_linear_scan.hl`**（Buffer: 0x1A30000）：RLS_MAXVARS=32，RLS_NREGS=8
  - `rls_add_interval(start, end)` + `rls_run()`：Poletto & Sarkar 1999 算法
  - `_rls_expire_old(pos)`：释放结束早于当前位置的活跃区间归还寄存器
  - `_rls_spill_at_interval(vr, end)`：无空闲寄存器时驱逐结束最晚的区间
  - 活跃集按 end 排序维护；溢出计数返回
  - 测试：10 个区间，8 个寄存器 → spills ≤ 2 → PASS

## Iteration 363 — pass_dce2.hl：增强死代码消除（SSA Phi 节点感知）

- **`pass_dce2.hl`**（Buffer: 0x1A20000）：DCE2_MAXINSTR=32，Phi 参数最多 4 个
  - `dce2_run()`：从 store/ret/branch 根指令出发，工作列表反向传播活跃性
  - `dce2_add_phi(dst)`：添加 Phi 节点；`dce2_phi_add_arg(i,r)` 注册 Phi 参数
  - Phi 节点传播：所有参数寄存器均被标记为活跃
  - 测试：5 条指令含 2 条死指令（const + mul），Phi + 加法 + ret 存活 → PASS

## Iteration 362 — pass_licm.hl：循环不变量外提

- **`pass_licm.hl`**（Buffer: 0x1A10000）：LICM_MAXINSTR=32，LICM_MAXLOOP=8
  - `licm_add_loop(header)` + `licm_add_body(lid,bb)`：定义循环结构
  - `licm_run()`：迭代至不动点，将循环体中操作数均在循环外定义的指令标记为可提升
  - 已提升指令的操作数视作循环外定义（传递性）
  - 测试：循环体含 const + add(均不变量) + loop-carried add → 提升 2 条 → PASS

## Iteration 361 — pass_gvn.hl：全局值编号（冗余消除）

- **`pass_gvn.hl`**（Buffer: 0x1A00000）：GVN_MAXINSTR=32，表达式哈希表大小 32
  - `gvn_run()`：为每条指令分配值号；相同 (op, vn0, vn1) 的指令复用已有值号并标记 eliminated
  - `gvn_add_instr(op,dst,src0,src1)` + 常量 op=4 的特殊去重
  - 测试：r2=a+b; r3=a+b（冗余）; r4=r2*r3 → eliminated=1（r3 消除）→ PASS

## Iteration 360 — min_enclosing_circle.hl：最小圆覆盖（Welzl O(n)）

- **`min_enclosing_circle.hl`**（Buffer: 0x19F0000）：MEC_MAXN=16 点，固定点坐标整数
  - `mec_add(x,y)`：添加点到待覆盖集合
  - `mec_compute()`：调用 Welzl 随机递归算法，确定最小覆盖圆
  - `_mec_c1/c2/c3`：1/2/3 点确定圆；3 点用外接圆公式（整数叉积+除法）
  - `_mec_inside(x,y)`：判断点是否在当前圆内（固定点 *1000 精度）
  - 测试：(0,0)(4,0)(2,3) → cx=2, cy≈0.833 → PASS

## Iteration 359 — bsgs.hl：Baby-step Giant-step 离散对数

- **`bsgs.hl`**（Buffer: 0x19E0000）：BSGS_M=32，哈希表大小 64（线性探测）
  - `bsgs_solve(a,b,p)`：解 a^x≡b (mod p)，x∈[0,p-1]，p 为素数
  - Baby steps：table[a^j mod p]=j，j∈[0,M)
  - Giant steps：枚举 b·(a^{-M})^i，查表匹配
  - `_bsgs_powmod(base,exp,mod)`：快速模幂（无 %，用减法模）
  - 测试：2^x=64 mod 101→x=6；3^x=27 mod 101→x=3 → PASS

## Iteration 358 — suffix_tree.hl：后缀树（Ukkonen O(n)）

- **`suffix_tree.hl`**（Buffer: 0x19D0000）：ST_MAXN=32，ST_MAXNODES=128
  - `st_build()`：Ukkonen 在线构造后缀树，O(n) 字符级扩展
  - `_st_extend(pos)`：处理位置 pos 的字符；维护活跃点 (an,ae,al) 和 rem
  - `st_count_occurrences(pat,plen)`：从根走模式路径，返回叶计数
  - 后缀链接 + 活跃点跳转保证 O(n) 均摊
  - 测试："banana"（编码为整数），occ("ana")=2 → PASS

## Iteration 357 — chtholly_tree.hl：珂朵莉树（ODT，区间推平）

- **`chtholly_tree.hl`**（Buffer: 0x19C0000）：ODT_MAXN=16 段
  - `odt_split_at(pos)`：确保 pos 为某段开始位置；O(n) 向右移动
  - `odt_assign(l,r,v)`：将 [l..r] 所有段合并为单段 (l,r,v)；O(n)
  - `odt_sum(l,r)`：区间 [l..r] 的段值 × 长度加权求和
  - 测试：[0..7]=0; assign [2..5]=3; sum=12, n=3 → PASS

## Iteration 356 — implicit_treap.hl：隐式 Treap（序列操作 + 懒翻转）

- **`implicit_treap.hl`**（Buffer: 0x19B0000）：IT_MAXN=33 节点
  - `_it_split(t,k)`：前 k 个 → it_sl，其余 → it_sr（全局双出参）
  - `_it_merge(l,r)`：按优先级合并，返回根
  - `_it_push(t)`：传播懒翻转标记（交换子节点 + 翻转子节点标记）
  - `it_reverse(l,r)`：三次 split/merge 实现区间翻转 O(log n)
  - 测试：build [1..5]，kth(1)=1；reverse [0..4] → kth(1)=5 → PASS

## Iteration 355 — wavelet_tree_range.hl：静态 Wavelet Tree（区间第 k 小）

- **`wavelet_tree_range.hl`**（Buffer: 0x19A0000）：WVR_N=8，WVR_LOG=3，值域 [0,7]
  - `wvr_build(n)`：逐层提取位，记录 cnt[level][i] = [0..i-1] 中向左走的前缀数
  - `wvr_kth(ql,qr,k)`：用 cnt 前缀差二分值域，O(log V) 查询
  - 测试：arr=[3,1,4,1]；kth(0..3,2)=1，kth(0..3,3)=3 → PASS

## Iteration 354 — broken_profile_dp.hl：轮廓线 DP（骨牌铺砌）

- **`broken_profile_dp.hl`**（Buffer: 0x1990000）：BPD_H=2 行固定，列扫 DP
  - `bpd_count(w)`：统计 2×w 网格 1×2 骨牌铺满方案数
  - `_bpd_fill(row, old_mask, new_mask)`：递归填列；读全局 `bpd_dp_src`
  - `bpd_col_last`：最后一列禁止向右延伸水平骨牌
  - 测试：2×4 → 5 种（Fibonacci F(5)）→ PASS

## Iteration 353 — digit_dp.hl：数位 DP（数字和等于目标值计数）

- **`digit_dp.hl`**（Buffer: 0x1980000）：DDM_MAXD=8，DDM_MAXS=36
  - `ddm_solve(n, target)`：统计 [0..n] 中十进制数字和等于 target 的整数个数
  - 逐位 DP：状态 dp[sum][tight]，按 MSB→LSB 逐层迭代
  - `_ddm_extract(n)`：十进制拆位写入 ddm_lim（MSB 优先）
  - 测试：[0..20] sum=2 → {2, 11, 20} → 3 → PASS

## Iteration 352 — bitmask_dp.hl：状压 DP（TSP）

- **`bitmask_dp.hl`**（Buffer: 0x1970000）：BDM_N=5，BDM_FULL=31
  - `bdm_tsp()`：最小哈密顿回路 O(2^N·N²)；dp[mask·N+v] = 访问 mask 中城市且末在 v 的最小代价
  - `_bdm_pow2(k)`：2^k（无位运算版）；位提取用 `bu-(bu/2)*2`
  - `bdm_set_dist(u,v,w)` / `bdm_get_dp(mask,v)`：外部设置与查询接口
  - 测试：5 城链 0-1-2-3-4-0，边权 1+2+3+4+5=15，其余边=100 → 最优 15 → PASS

## Iteration 351 — poly_sqrt.hl：多项式开根 + Horner 求值

- **`poly_sqrt.hl`**（Buffer: 0x1960000）：PSQ_N=16，mod p=998244353
  - `PSQ_INV2 = 499122177`（inv(2) mod p 预计算）
  - `psq_sqrt(n)`：g = sqrt(f) mod x^n，O(n^2) 递推 g[k] = inv2*(f[k] - Σg[i]*g[k-i])
  - `psq_eval(deg, val)`：Horner 法多点求值 f(val) mod p
  - 测试：f = (1+x)^2 → sqrt = [1,1,0,0]，f(3)=16 → PASS

## Iteration 350 — poly_ln_exp.hl：多项式 ln + exp

- **`poly_ln_exp.hl`**（Buffer: 0x1950000）：PLE_N=8，mod p=998244353
  - `ple_exp(n)`：g = exp(f)，f[0]=0；递推 g[k]=(1/k)*Σ i*f[i]*g[k-i]
  - `ple_ln(n)`：g = ln(f)，f[0]=1；递推 g[k]=f[k]-(1/k)*Σ i*g[i]*f[k-i]
  - `_ple_inv(a)`：Fermat 小定理 a^(p-2) mod p
  - 测试：ln(exp(x)) mod x^5 = [0,1,0,0,0] → PASS

## Iteration 349 — poly_inv.hl：多项式求逆（Newton 迭代）

- **`poly_inv.hl`**（Buffer: 0x1940000）：PINV_N=16，mod p=998244353
  - `pinv_compute(n)`：Newton 迭代 g_{k+1}=g_k*(2-f*g_k)，精度每次翻倍至 n
  - `_pinv_step(n)`：单次 Newton 步，O(n^2) 多项式乘法
  - `_pinv_powmod`：模幂，用于 f[0]^{-1} 初始化
  - 测试：f=1+x，验证 f*g ≡ 1 mod x^4（四个系数全正确）→ PASS

## Iteration 348 — bridge_tree.hl：桥树（边双连通分量 + 桥缩点）

- **`bridge_tree.hl`**（Buffer: 0x1930000）：BT_V=8, BT_MAXE=16
  - `bt_add_edge(u,v)`：无向边加入邻接表
  - `_bt_dfs(u, par_ei)`：DFS 计算 disc/low，标记桥边（`bt_is_bridge[ei]=1`）
  - `_bt_assign(u, comp_id)`：DFS 在非桥边上扩散，划分边双连通分量
  - `bt_build()`：两阶段（找桥 + 分量赋值），结果：`bt_n_bridges`、`bt_n_comp`
  - 测试：5 顶点 {0-1, 1-2, 2-0, 2-3, 3-4}，桥 = {2-3, 3-4}，分量 = {0,1,2},{3},{4} → n_bridges=2, n_comp=3 → PASS

## Iteration 347 — block_cut_tree.hl：块割树（双连通分量 + 割点缩点）

- **`block_cut_tree.hl`**（Buffer: 0x1920000）：BCT_V=8, BCT_MAXE=16
  - `bct_add_edge(u,v)`：无向边
  - `_bct_dfs(u, par_v)`：DFS + 边栈（slot 索引），low-link 法识别割点和双连通块
    - 遇到 `low[v] >= disc[u]`：从栈弹出一个块，非根顶点标记为割点
    - 根顶点：子树数 > 1 时标记为割点
  - `bct_build()`：对所有未访问顶点调用 DFS，再统计 `bct_n_cut`
  - 测试：5 顶点 {0-1, 1-2, 2-0, 2-3, 3-4}，割点 = {2,3}，块 = {0,1,2},{2,3},{3,4} → n_cut=2, n_blocks=3 → PASS

## Iteration 346 — dinic.hl：Dinic 最大流 O(V²E)

- **`dinic.hl`**（Buffer: 0x1910000）：DI_V=8, DI_E=128（正向 + 反向配对）
  - `di_add_edge(u,v,cap)`：添加有向边及容量为 0 的反向边
  - `_di_rev(e)`：反向边索引（奇偶互换：偶→+1，奇→-1）
  - `_di_bfs(s,t)`：BFS 构建分层图（`di_level[]`），可达返回 1
  - `_di_dfs(u,t,pushed)`：递归 DFS 当前弧优化阻塞流
  - `di_max_flow(s,t)`：外层 BFS 循环 + 内层多路增广，返回最大流
  - 测试：S=0,T=3，边 {0→1(10), 0→2(10), 1→3(10), 2→3(10)}，期望 flow=20 → PASS

## Iteration 345 — half_plane.hl：半平面交（Sutherland-Hodgman）

- **`bare-kernel/hl/half_plane.hl`** 新增（~140 行）
  - HP_MAX=64，HP_HMAX=16；`hp_pts_x/y[64]`（当前多边形）、`hp_tmp_x/y[64]`（裁剪缓冲）
  - 半平面表示：有向直线 (ax,ay)→(bx,by)，左侧为内侧
  - `hp_set_box(x0,y0,x1,y1)` — 设置初始矩形边界多边形（4 顶点 CCW）
  - `hp_add_hp(ax,ay,bx,by)` — 添加半平面约束（最多 16 个）
  - `_hp_clip_one(...)` — Sutherland-Hodgman 单次裁剪：逐边判断 p1/p2 内外，精确整数交点
  - `hp_clip_all()` — 顺序应用所有半平面裁剪
  - `hp_area2()` — 结果多边形面积×2（Shoelace 公式）
  - `hp_inside(px,py)` — 点可行性检验（对所有半平面测试）
  - 测试：边界框 (-10,-10)-(10,10) 切去 x+y>10 → 五边形 n=5,area2=700 PASS
  - Buffer: 0x1900000

## Iteration 344 — rotating_calipers.hl：旋转卡壳（最远点对 + 最小包围矩形）

- **`bare-kernel/hl/rotating_calipers.hl`** 新增（~100 行）
  - RC_MAX=64；`rc_px/py[64]` 凸多边形顶点（CCW 顺序）
  - `_rc_next(i)` — 循环下标；`_rc_dist2(i,j)` — 点间距平方；`_rc_cross3(a,b,c)` — 有向叉积
  - `rc_diameter2()` — 旋转卡壳 O(n)：初始化对极点 j，逐边推进直到叉积不增；返回最大距离平方
  - `rc_mbr_area()` — 最小包围矩形面积 O(n²)：对每条边计算垂直/沿边方向的极值，scaled/d² 最小化
  - 测试：正方形 (0,0),(6,0),(6,6),(0,6) → diameter²=72，MBR面积=36 PASS
  - Buffer: 0x18F0000

## Iteration 343 — geometry_2d.hl：二维计算几何基础原语

- **`bare-kernel/hl/geometry_2d.hl`** 新增（~105 行）
  - G2_MAX=64；`g2_px/py[64]` 多边形顶点，`g2_n` 顶点数
  - `g2_cross(ax,ay,bx,by)` — 二维叉积（ax*by - ay*bx）
  - `g2_dot(ax,ay,bx,by)` — 点积；`g2_dist2` — 距离平方
  - `g2_area2()` — Shoelace 公式，有符号面积×2（CCW>0）
  - `g2_pip(qx,qy)` — 射线法点在多边形内判断（整数精确）
  - `g2_seg_inter(ax,ay,bx,by,cx,cy,dx,dy)` — 线段严格相交判断（叉积符号法）
  - 测试：三角形(0,0),(10,0),(5,10)：area2=100，pip(5,3)=1，pip(11,3)=0，seg_inter=1 PASS
  - Buffer: 0x18E0000

## Iteration 342 — linear_basis.hl：XOR 线性基（高斯消元）

- **`bare-kernel/hl/linear_basis.hl`** 新增（~100 行）
  - LB_BITS=30，`lb_basis[30]`：第 i 位存储最高位为 i 的基向量
  - `_lb_xor(a,b)` — 30-bit 逐位 XOR（无原生 XOR，用除法位提取）
  - `_lb_bit(x,pos)` — 取 x 第 pos 位（幂次循环计算）
  - `lb_insert(x)` — 高斯消元插入：从高位到低位扫描，消去已有基向量，独立则存入，返回 1；否则返回 0
  - `lb_query_max()` — 贪心逐位尝试 XOR 当前结果与基向量，取最大值
  - `lb_size()` — 返回线性无关基向量数
  - 测试：插入 {1,2,3,4}：3=1⊕2 相关(0)，基={4,2,1}，max_xor=7，size=3 PASS
  - Buffer: 0x18D0000

## Iteration 341 — pollard_rho.hl：Pollard-Rho 大数因式分解

- **`bare-kernel/hl/pollard_rho.hl`** 新增（~117 行）
  - 依赖 miller_rabin.hl（`mr_is_prime`、`_mr_mod`）
  - Floyd 循环检测：f(x)=(x²+c) mod n，c 从 1 试到 19
  - `pr_factor(n)` — 返回 n 的一个非平凡因子；步数超 2000 或 c 耗尽则返回 n
  - `pr_factorize(n)` — 栈式递推完全分解，结果存入 `pr_factors[0..pr_fcount-1]`
  - `pr_product()` — 验证所有因子之积
  - 测试：factorize(84)→4 因子,积=84；factorize(997)→1 因子,f[0]=997 PASS
  - Buffer: 0x18C0000

## Iteration 340 — miller_rabin.hl：Miller-Rabin 素性测试

- **`bare-kernel/hl/miller_rabin.hl`** 新增（~121 行）
  - 确定性版：见证者 {2,3,5,7}，对 n < 3,215,031,751 完全正确
  - `_mr_modpow(base,exp,mod)` — 平方-乘法快速幂
  - `_mr_witness_check(a,n,d,r)` — 单轮 Miller-Rabin 见证检测
  - `mr_is_prime(n)` — 1=素数，0=合数（n<2/偶数快速返回，写 n-1=2^r·d 后逐证人检测）
  - `mr_next_prime(n)` / `mr_count_primes(limit)` — 素数工具函数
  - 测试：prime(997)=1, prime(7919)=1, comp(100)=0, comp(1001)=0, next(100)=101 PASS
  - Buffer: 0x18B0000

## Iteration 339 — bitset_ops.hl：固定位图（AND/OR/popcount）

- **`bare-kernel/hl/bitset_ops.hl`** 新增（~110 行）
  - 18 个 30-bit 字，覆盖 512 位（BTS_WBITS=30，BTS_WORDS=18）
  - `bts_a[18]` / `bts_b[18]`：两个独立位图，所有变更操作针对 bts_a
  - `bts_set(i)` / `bts_clear(i)` / `bts_get(i)` — 单位操作，幂次通过 `_bts_pw` 计算
  - `_bts_xor_word(x,y)` — 逐位 XOR（无原生 XOR，位提取用除法取模替代）
  - `_bts_and_word(x,y)` — `(x+y-xor)/2`；`_bts_or_word(x,y)` — `x+y-and`
  - `bts_and_a()` / `bts_or_a()` — 字级 AND/OR 批处理
  - `bts_count()` — 全图 popcount，逐字逐位统计
  - 测试：a={0,3,7,100} count=4；AND b={3,7,100} → count=3；OR b={3,7,100,200} → count=5 PASS
  - Buffer: 0x18A0000

## Iteration 338 — knuth_dp.hl：Knuth DP 优化（最优合并石子）

- **`bare-kernel/hl/knuth_dp.hl`** 新增（~80 行）
  - KN_MAX=16，`kn_w[16]` 石子权重，`kn_s[17]` 前缀和
  - `kn_dp[256]`（kn_dp[i*16+j]）/ `kn_opt[256]`（最优分割点）
  - `kn_build(n)` — 按长度递推，Knuth 括号约束 opt[i][j-1]≤opt[i][j]≤opt[i+1][j]
  - 时间复杂度 O(n²)（朴素 O(n³) 降维）
  - `kn_cost()` — 返回 kn_dp[0][n-1] 最小合并总代价
  - 测试：石子 [1,2,3,4] → 最优代价=19 PASS
  - Buffer: 0x1890000

## Iteration 337 — palindrome_dp.hl：回文划分最小切割 DP

- **`bare-kernel/hl/palindrome_dp.hl`** 新增（~80 行）
  - PL_MAX=32，`pl_s[32]` 整数序列，`pl_is[1024]`（pl_is[i*32+j]=1 iff [i,j] 回文）
  - `pl_build(n)` — O(n²) 填表：长度 1/2 直接判断，长度≥3 扩展 → DP 求最小切割
  - `pl_min_cuts()` — 返回 pl_dp[n-1]；`pl_pal(i,j)` — 回文谓词
  - 测试：`aab`=[0,0,1] → 1 cut；`abcba`=[0,1,2,1,0] → 0 cuts PASS
  - Buffer: 0x1880000

## Iteration 336 — seg_merge.hl：稀疏线段树合并

- **`bare-kernel/hl/seg_merge.hl`** 新增（~100 行）
  - 动态开点稀疏线段树，坐标域 [0,63]，节点池 SM_POOL=512
  - `sm_update(root,lo,hi,pos,val)` — 插入权值，路径上动态分配节点
  - `sm_query(root,lo,hi,l,r)` — 区间权值和查询 O(log n)
  - `sm_merge(u,v,lo,hi)` — 破坏性合并两棵树（复用 u 的节点）O(重叠节点数)
  - `sm_roots[32]` — 多棵树根数组，支持 shell 命令独立操作
  - 测试：树0(pos3+5,pos10+4)，树1(pos7+3,pos10+5)，合并后总和=17，区间[5,15]=12
  - Buffer: 0x1870000

## Iteration 335 — ntt.hl：数论变换（NTT mod 998244353）

- **`bare-kernel/hl/ntt.hl`** 新增（~130 行）
  - MOD=998244353=119×2²³+1，原根 g=3
  - 无 `%` 运算符：取模用 `v - (v/MOD)*MOD`；无 XOR/AND：位提取用算术
  - `_ntt_mod(v)` / `_ntt_mpow(base,exp)` — 模运算与快速幂
  - `_ntt_get/_ntt_set` 通过 `ntt_cur`（0=a,1=b,2=c）调度数组访问（规避数组传参限制）
  - `_ntt_run(n,inv)` — 蝴蝶变换（位逆序置换 + 迭代 DIT）
  - `ntt_multiply(na,nb)` — 多项式卷积：补零到 2 的幂，NTT→逐点乘→INTT
  - 测试：[1,2,3]×[4,5,6]=[4,13,28,27,18] PASS
  - Buffer: 0x1860000

## Iteration 334 — quickselect.hl：QuickSelect + QuickSort

- **`bare-kernel/hl/quickselect.hl`** 新增（~80 行）
  - Lomuto 分区，末位元素为基准，1-indexed k（0-based 数组下标）
  - `_qs_part(lo,hi)` — Lomuto 划分，返回 pivot 最终位置
  - `_qs_sel(lo,hi,k)` — 递归 QuickSelect，O(n) 期望
  - `qs_kth(k)` — 第 k 小元素（0-indexed）
  - `_qs_sort(lo,hi)` / `qs_sort()` — 递归 QuickSort，O(n log n) 期望
  - QS_MAX=64，数据存于 `qs_data[64]`，`qs_n` 设置有效长度
  - 测试：[7,2,1,6,5,3,4,8] kth(3)=4，sort→sorted[0]=1,sorted[7]=8 PASS
  - Buffer: 0x1850000

## Iteration 333 — link_cut_tree.hl：Link-Cut Tree（动态森林路径查询）

- **`bare-kernel/hl/link_cut_tree.hl`** 新增（~220 行）
  - 辅助 Splay 树 + 路径翻转懒标记（`lk_rev[]`），1-indexed 节点 1..LK_N=32
  - `lk_access(v)` — 打通 v 到根的首选路径，O(log n) 均摊
  - `lk_makeroot(v)` — 换根（access + toggle rev）
  - `lk_findroot(v)` — 找树根（access 后向左走到底）
  - `lk_link(u,v)` / `lk_cut(u,v)` — 加边/删边
  - `lk_connected(u,v)` — 连通性查询
  - `lk_pathsum(u,v)` — 路径权值和（makeroot + access → lk_sum[v]）
  - 测试：链 1-2-3-4-5，sum(1,5)=15，cut(3,4)，conn(1,5)=0，sum(1,3)=6
  - Buffer: 0x1840000

## Iteration 332 — seg_beats.hl：吉司机线段树（Segment Tree Beats）

- **`bare-kernel/hl/seg_beats.hl`** 新增（~165 行）
  - 每节点维护 max/max2/maxcnt/sum/lazy_chmin，支持区间 chmin + 区间求和
  - `_sb_apply(v,val)` — O(1) 应用 chmin 当 val > max2：sum -= (max-val)*maxcnt
  - `_sb_chmin(v,lo,hi,l,r,val)` — 当 val ≤ max2 时递归，O(n log² n) 均摊
  - `sb_build(n)` / `sb_query(l,r)` — 从 sb_data[] 建树，区间求和
  - 测试：[5,3,7,2,8,4,6,1] → chmin(0,7,5)→sum=30，chmin(2,5,3)→sum=25，sum[2..5]=11
  - Buffer: 0x1830000

## Iteration 331 — monotone_queue.hl：单调队列（滑动窗口 min/max）

- **`bare-kernel/hl/monotone_queue.hl`** 新增（~85 行）
  - `mq_slide_min(n,k)` — 填充 mq_min_res[i] = min(mq_data[i-k+1..i])，O(n)
  - `mq_slide_max(n,k)` — 填充 mq_max_res[i] = max(...)，O(n)
  - 单调递增/递减双端队列：deque 存下标，维护窗口内单调性
  - 测试：data=[3,1,4,1,5,9,2,6], k=3 → min[2]=1, min[5]=1, max[2]=4, max[7]=9
  - Buffer: 0x1820000

## Iteration 330 — dc_dp.hl：Divide-and-Conquer DP 优化

- **`bare-kernel/hl/dc_dp.hl`** 新增（~90 行）
  - `_dc_cost(i,j)` — 代价函数 (j-i)²，满足四边形不等式
  - `_dc_solve(lo,hi,opt_lo,opt_hi)` — 递归 D&C：mid 处枚举最优分割点，向左右子区间传播单调约束
  - `dc_run(n)` — 从 dc_prev[] 计算一层 dp[]，返回 dp[n-1]；O(n log n)
  - 测试：dc_prev[i]=i²，n=5 → dp=[0,1,2,5,8]，opt 单调非降
  - Buffer: 0x1810000

## Iteration 329 — li_chao_tree.hl：Li Chao 树（最小直线查询）

- **`bare-kernel/hl/li_chao_tree.hl`** 新增（~110 行）
  - `lc_add_line(m,b)` — 插入直线 y=mx+b，内部 `_lc_add` 递归在中点比较交换
  - `lc_query(x)` — 查询所有直线在 x 处的最小值，O(log n)
  - `lc_eval(node,x)` — 节点直线求值，无直线返回 LC_INF=999999
  - 线段树覆盖 x∈[0,63]，LC_SZ=256 节点（1-indexed）
  - 测试：直线 (3,0)+(1,4)+(-1,10) → q(0)=0, q(2)=6, q(5)=5
  - Buffer: 0x1800000

## Iteration 328 — trie.hl：前缀字典树

- **`bare-kernel/hl/trie.hl`** 新增（~100 行）
  - `tr_insert(wlen)` — 插入 tr_word[0..wlen-1]，沿路更新 tr_cnt[]（前缀计数）
  - `tr_search(wlen)` — 精确匹配，返回单词出现次数（tr_end[]）
  - `tr_prefix(plen)` — 前缀计数，返回经过该前缀节点的总插入次数
  - 字母表 0-9（TR_ALPHA=10），最多 TR_MAX=128 节点，tr_child[node×10+c]=-1 表示无子
  - 测试：insert [1,2,3]×2 + [1,2,4]×1 → search(123)=2, prefix(12)=3, search(124)=1, prefix(1)=3
  - Buffer: 0x17F0000

## Iteration 327 — game_theory.hl：博弈论（Sprague-Grundy + Nim）

- **`bare-kernel/hl/game_theory.hl`** 新增（~120 行）
  - `sg_compute(n)` — 计算 sg_memo[0..n]，移动集合 {1,2,3}，MEX of 3 前驱
  - `_gt_mex3(v1,v2,v3)` — 从 0 起找第一个不在 {v1,v2,v3} 中的值（-1 表示缺失）
  - `_gt_xor2(a,b)` — 纯算术 XOR 模拟，逐位提取（aa-(aa/2)*2），O(bits)
  - `gt_nim_winner()` — XOR 所有 gt_piles[0..gt_npiles-1]，非零则先手胜
  - 测试：sg[4]=0, sg[7]=3, xor(3,5)=6, nim([3,5,7])=winner=1
  - Buffer: 0x17D0000

## Iteration 326 — interval_dp.hl：区间 DP（矩阵链乘）

- **`bare-kernel/hl/interval_dp.hl`** 新增（~100 行）
  - `idp_matchain(n)` — n 个矩阵链乘最优括号，O(n³) 区间 DP
  - 自底向上：按长度填充 dp[i][j]，枚举分割点 k
  - `dp[i][j] = min(dp[i][k] + dp[k+1][j] + dims[i]*dims[k+1]*dims[j+1])`
  - IDP_MAX=16 步长，IDP_INF=999999，最多 16 矩阵
  - 测试：n=3, dims=[1,2,3,4] → dp[0][1]=6, dp[1][2]=24, opt=18
  - Buffer: 0x17C0000

## Iteration 325 — string_hash.hl：多项式滚动哈希

- **`bare-kernel/hl/string_hash.hl`** 新增（~100 行）
  - `sh_build(n)` — 构建前缀哈希 sh_hash[] + 幂次 sh_pow[]，O(n)
  - `sh_query(l,r)` — O(1) 子串哈希：h[r+1] - pow[r-l+1]*h[l] (mod SH_MOD)
  - `sh_prep_pat(n)` — 计算模式哈希 sh_pat_h，用于 Rabin-Karp
  - `sh_find()` — 线性扫描匹配，返回首次出现位置（-1 未找到）
  - SH_BASE=31，SH_MOD=100003；负数哈希加 MOD 修正
  - 测试：text=[1,2,3,2,3,4], pat=[2,3] → find()=1
  - Buffer: 0x17B8000



- **`bare-kernel/hl/number_theory.hl`** 新增（~130 行）
  - `nt_gcd_ext(a,b)` — 扩展欧几里得，设全局 nt_gcd/nt_x/nt_y（ax+by=gcd）
  - `nt_mod_inv(a,m)` — 模逆元（gcd=1时存在），结果规范化为正值
  - `nt_crt(r1,m1,r2,m2)` — 中国剩余定理（互质模数），Garner 公式
  - `nt_euler_phi(n)` — Euler φ 函数：逐质因子迭代，`result = result/p*(p-1)`
  - `nt_sieve(n)` — Eratosthenes 筛法，输出 nt_primes[] + nt_prime_cnt
  - 测试：sieve(30)=10, phi(12)=4, inv(3,7)=5, crt(2,3,3,5)=8
  - Buffer: 0x17B0000

## Iteration 323 — matrix_expo.hl：矩阵快速幂

- **`bare-kernel/hl/matrix_expo.hl`** 新增（~110 行）
  - ME_K=2（2×2矩阵），me_pool[16] 存 3 个矩阵槽：base/result/temp
  - `_me_mul(a_off,b_off,c_off)` — 三重嵌套 while 矩阵乘法
  - `me_pow(n)` — 二进制快速幂：奇数位 result*=base，每步 base 自乘
  - `me_set/me_get` — 矩阵元素读写（行优先 offset + r*K + c）
  - 测试：Fibonacci [[1,1],[1,0]]^10 → result[0][1]=F(10)=55, result[0][0]=F(11)=89
  - Buffer: 0x17A0000

## Iteration 322 — convex_hull_trick.hl：凸包优化（CHT）

- **`bare-kernel/hl/convex_hull_trick.hl`** 新增（~90 行）
  - 最小值 CHT：斜率递减顺序加线，下凸包维护
  - `_cht_bad(l1,l2,m3,b3)` — 交叉乘积判断 l2 是否被 l1+候选线覆盖
  - `cht_add_line(m,b)` — 加线时弹出被覆盖的中间线，O(1) 均摊
  - `cht_query(x)` — 二分搜索最优线，O(log n)
  - 测试：lines (3,0)+(1,4)+(-1,10) → q(0)=0, q(2)=6, q(5)=5
  - Buffer: 0x1790000

## Iteration 321 — sqrt_decomp.hl：sqrt 分块

- **`bare-kernel/hl/sqrt_decomp.hl`** 新增（~100 行）
  - 块大小 SQ_B=8，最多 SQ_MAX_B=8 块，支持 n≤64
  - `sq_update(pos, val)` — O(1) 单点加，同时更新 sq_block[b]
  - `sq_range_add(l, r, val)` — 两侧偏块逐元素更新；中间整块用 lazy delta + block_sum 更新 O(√n)
  - `sq_query(l, r)` — 偏块逐元素求和 + lazy；整块直接用 sq_block[b] O(√n)
  - 测试：n=16，点更新(1,10)+(9,5)→q=15；range_add(4,12,1)→q=24；q(5,10)=11
  - Buffer: 0x1780000

## Iteration 320 — mo_algorithm.hl：Mo 离线分块

- **`bare-kernel/hl/mo_algorithm.hl`** 新增（~110 行）
  - 插入排序按 (block(l), r) 排序查询；块大小 MO_BLOCK=8
  - 维护当前窗口 [mo_curl, mo_curr] + 累积和 mo_csum
  - 4 阶段扩展/收缩：expand-right → expand-left → shrink-right → shrink-left
  - `mo_add_query(l,r)` — 记录查询；`mo_run()` — 按排序顺序处理所有查询
  - 测试：arr=[1..8]，q=[0,2]=6，q=[1,4]=14，q=[3,7]=30
  - Buffer: 0x1770000，MO_MAX_N=64，MO_MAX_Q=32

## Iteration 319 — splay_tree.hl：伸展树

- **`bare-kernel/hl/splay_tree.hl`** 新增（~150 行）
  - 自调整 BST，均摊 O(log n)；访问节点自动 splay 到根
  - `_sp_rotate(x)` — 单次旋转（右旋/左旋），维护 parent/child 链
  - `_sp_splay(x)` — while 循环迭代：zig / zig-zig / zig-zag 三类旋转
  - `sp_insert(k)` — BST 下探 + splay 新节点到根
  - `sp_find(k)` — BST 搜索 + splay 最近访问节点；返回节点索引或 -1
  - `sp_min()` / `sp_max()` — 走到最左/最右叶后 splay
  - 测试：insert(5,3,7,1,4) → min=1, max=7, find(3)≥0, find(9)=-1
  - Buffer: 0x1760000，SP_MAX=64

## Iteration 318 — rollback_dsu.hl：可回滚 DSU

- **`bare-kernel/hl/rollback_dsu.hl`** 新增（~110 行）
  - 按秩合并（无路径压缩），支持 O(1) 回滚
  - `rdu_union(a,b)` — 找根，小秩接到大秩下，历史栈记录 (child, old_parent, root, old_rank)
  - `rdu_rollback()` — 从历史栈弹出一步，恢复 parent 和 rank，返回 0 表示栈空
  - `rdu_same(a,b)` — 判断同集合；`rdu_find(x)` — 无压缩路径查根
  - 测试：union(0,1), union(2,3), union(0,2) → same(0,3)=1；rollback() → same(0,3)=0, same(0,1)=1
  - Buffer: 0x1750000，RDU_MAX_N=32，RDU_HIST_MAX=128

## Iteration 317 — persistent_seg.hl：可持久化线段树

- **`bare-kernel/hl/persistent_seg.hl`** 新增（~120 行）
  - 写时复制节点池；每次更新沿路创建 O(log n) 新节点
  - `ps_build(n)` — 构建版本 0（全零叶）；返回根节点编号
  - `ps_update(ver,n,pos,addval)` — 从 ver 版本创建新版本，单点加法
  - `ps_query(ver,n,ql,qr)` — 查询版本 ver 中 [ql,qr] 区间和
  - `_ps_copy_node(src)` — 复制节点到新池位置，实现版本隔离
  - 测试：n=4，2 次更新 → q(v0)=0, q(v1)=5, q(v2)=8
  - Buffer: 0x1740000，PS_MAX_NODES=256，PS_MAX_VER=16

## Iteration 316 — io_uring.hl：异步 I/O 环形缓冲

- **`bare-kernel/hl/io_uring.hl`** 新增（~120 行）
  - SQ（提交队列）16 槽 + CQ（完成队列）32 槽；整数算术取模模拟环形索引
  - `ior_submit(op,fd,buf,ilen)` — 入队 SQ，返回 request_id；队满返回 -1 并计 dropped
  - `ior_process()` — 消费 SQ 全部条目，写入 CQ，返回处理数
  - `ior_consume()` — 弹出 CQ 一条记录，返回 request_id
  - `ior_cq_pending()` — 当前未消费 CQ 条目数
  - 操作码：IOR_READ=0, IOR_WRITE=1, IOR_ACCEPT=2, IOR_SEND=3, IOR_RECV=4
  - 测试：提交 3 个操作 → process() 返回 3，cq_pending()=3
  - Buffer: 0x1730000，IOR_SQ_SIZE=16，IOR_CQ_SIZE=32

## Iteration 315 — codegen.hl：窥孔优化器 + 死代码消除

- **`bare-kernel/hl/codegen.hl`** 新增（~110 行）
  - 窥孔优化三模式：① COPY dst=src（恒等拷贝）→ 删除；② ADD dst,src,0 → COPY；③ MUL dst,src,1 → COPY
  - `cg_peephole()` — 迭代扫描直到无变化，`cg_opts` 累计优化次数
  - `cg_dce()` — 单趟死寄存器消除：标记所有被引用的 dst，未被引用的非 RET 指令标记为 dead
  - `cg_live[]` — 指令活跃标志（0=已删除）；`cg_reg_used[32]` — 寄存器使用标记
  - 测试：3 条指令（ADD+0/COPY identity/MUL×1）→ cg_peephole() 返回 3
  - Buffer: 0x1720000，CG_MAX_INST=64，CG_MAX_REG=32

## Iteration 314 — regalloc.hl：图着色寄存器分配

- **`bare-kernel/hl/regalloc.hl`** 新增（~90 行）
  - 贪心图着色，K=4 个物理寄存器（RA_K）；干涉图 16×16 邻接矩阵
  - `ra_add_interfere(u,v)` — 添加干涉边（对称）
  - `_ra_choose_color(v)` — 扫描邻居已分配颜色，用 `ra_tmp_used[K]` 标记占用，返回最低可用色
  - `ra_run()` — 按变量编号顺序贪心着色；无可用色则标记 spill（color=-1）
  - 测试：4 变量 干涉（0-1,1-2,2-3,0-2），K=4 → colors=[0,1,2,0]，spills=0
  - Buffer: 0x1710000，RA_MAX_VAR=16

## Iteration 313 — ir.hl：SSA 中间表示

- **`bare-kernel/hl/ir.hl`** 新增（~95 行）
  - 9 种操作码：NOP/COPY/ADD/SUB/MUL/PHI/JUMP/BRANCH/RET
  - `ir_new_bb()` — 创建基本块，设置 ir_cur_bb
  - `ir_emit(bb, op, dst, src1, src2)` — 追加指令，PHI 自动计数
  - `ir_add_edge(pred, succ)` — 添加控制流边（ir_bb_succ0/succ1）
  - `ir_phi_count` — phi 节点数；`ir_bb_size[]` — 每 BB 指令数
  - 测试：3 BB（BB0→BB2, BB1→BB2）+ 1 phi → ir_n=7, ir_bb_n=3, ir_phi_count=1
  - Buffer: 0x1700000，IR_MAX_INST=64，IR_MAX_BB=16

## Iteration 312 — z_function.hl：Z 函数

- **`bare-kernel/hl/z_function.hl`** 新增（~70 行）
  - Gusfield 1997，O(n)；zf_z[i] = s 和 s[i..] 最长公共前缀长度
  - 维护最右延伸区间 [l,r]：若 i<r 则用镜像值 min(r-i, z[i-l]) 初始化 zf_z[i]
  - 朴素扩展内层用嵌套 if/else（H-L 无 break → done-flag）
  - `zf_result` = max(zf_z[1..n-1])，可用于子串重复检测
  - 测试："abcabc"=[0,1,2,0,1,2] → z=[6,0,0,3,0,0]，max=3
  - Buffer: 0x16F0000，ZF_MAX_N=32
  - Shell 命令：`zf init  zf add <c>  zf run  zf val <i>  zf max  zf test`

## Iteration 311 — lyndon.hl：Lyndon 分解（Duval 算法）

- **`bare-kernel/hl/lyndon.hl`** 新增（~70 行）
  - Duval 1983，O(n) 时间 O(1) 额外空间；输出字典序非增的 Lyndon 词序列
  - 三指针 i/j/k：j 跟踪当前 Lyndon 词比较位置，k 向前扫描
  - 当 s[j]>s[k] 时（遇到更小字符）提前终止：saved_k=k 保存分断点，k=lyn_n 强制退出
  - 输出阶段：`while i<=j` 反复写出长度 saved_k-j 的 Lyndon 词并推进 i
  - `lyn_starts[]` + `lyn_lens[]` 记录各 Lyndon 词位置和长度
  - 测试："bab"=[1,0,1] → count=2，[start=0,len=1,"b"]+[start=1,len=2,"ab"]
  - Buffer: 0x16E0000，LYN_MAX_N=32
  - Shell 命令：`lyn init  lyn add <c>  lyn run  lyn count  lyn test`

## Iteration 310 — burrows_wheeler.hl：Burrows-Wheeler 变换

- **`bare-kernel/hl/burrows_wheeler.hl`** 新增（~90 行）
  - Burrows & Wheeler 1994，O(n²) 循环旋转排序（n≤32 足够）
  - `_bwt_cmp_rot(a, b)` — 逐字符比较循环旋转 a 和 b，取模用算术：`sum - (sum/n)*n`
  - `_bwt_sort_sa()` — 对旋转序号的插入排序；比较结果决定插入位置
  - `bwt_run()` — 提取已排序旋转的最后一列：BWT[i]=s[(sa[i]-1+n)%n]；找 sa[i]==0 行定位 bwt_orig
  - 测试："aab"=[0,0,1] → bwt_out=[1,0,0]（"baa"），bwt_orig=0
  - Buffer: 0x16D0000，BWT_MAX_N=32
  - Shell 命令：`bwt init  bwt add <c>  bwt run  bwt orig  bwt char <i>  bwt test`

## Iteration 309 — eertree.hl：回文树（Palindromic Tree）

- **`bare-kernel/hl/eertree.hl`** 新增（~95 行）
  - Mikhail Rubinchik 2014，O(n) 构建；`et_count` = 不同非空回文子串数量
  - 两个根节点：state 0（虚根 len=-1，任意字符匹配）、state 1（空串根 len=0）
  - `_et_get_suf(p, i)` — 从 p 向上走后缀链接，找到可以左右扩展 s[i] 的最长回文后缀
  - `et_add(c)` — 若转移不存在则创建新节点（len=父回文len+2），查找后缀链接
  - 新节点后缀链接：len==1→state 1；否则对 link[p] 再次调用 `_et_get_suf` 取转移
  - 测试："aaaa" → et_count=4（"a"/"aa"/"aaa"/"aaaa"）
  - Buffer: 0x16C0000，ET_MAX_ST=36，ET_ALPHA=26
  - Shell 命令：`et init  et add <c>  et count  et sz  et test`

## Iteration 308 — manacher.hl：Manacher 最长回文子串

- **`bare-kernel/hl/manacher.hl`** 新增（~85 行）
  - Manacher 1975，O(n)，构造分隔符变换串（char 26 为分隔符）
  - `_man_build()` — 将 s[0..n-1] 变换为 s'[0..2n]（奇长，含分隔）
  - `man_run()` — 标准 Manacher 扩展：维护右边界 r 和中心 c，镜像取 min(p[mirror], r-i)
  - `man_result` — 最长回文半径（等于原串中最长回文子串长度）
  - 内层扩展用嵌套 if/else（H-L 无 else if，无 break→done-flag）
  - 测试："abba"=[0,1,1,0] → man_result=4
  - Buffer: 0x16B0000，MAN_MAX=64
  - Shell 命令：`man init  man add <c>  man run  man len  man test`

## Iteration 307 — suffix_automaton.hl：后缀自动机（SAM）

- **`bare-kernel/hl/suffix_automaton.hl`** 新增（~100 行）
  - Blumer et al. 1985，O(n) 在线构建；输入字符 int 0..25
  - 每个状态：`sam_len[]`（最长子串长）、`sam_link[]`（后缀链接）、`sam_trans[]`（26 路转移）
  - `sam_extend(c)` — 创建新状态 cur；向上遍历 link 添加转移；若遇已有转移则 clone（无 XOR，用 saved 记录分岔点）
  - 不可变性关键：clone 的 len=分岔点 len+1，接管 q 的转移和链接；重路由上方所有指向 q 的 c-转移 → clone
  - `sam_count_substr()` = Σ(len[i]-len[link[i]]) for i=1..sz-1
  - 测试："abab"=[0,1,0,1] → distinct=7（a/b/ab/ba/aba/bab/abab）
  - Buffer: 0x16A0000，SAM_MAX_ST=64，SAM_ALPHA=26
  - Shell 命令：`sam init  sam add <c>  sam count  sam sz  sam test`

## Iteration 306 — dominator.hl：支配树

- **`bare-kernel/hl/dominator.hl`** 新增（~110 行）
  - Cooper et al. 2001 迭代算法：RPO 序 + 固定点迭代，O(n²)
  - `_dom_build_rpo()` — 后序 DFS + 原地逆置 → RPO 顺序；`dom_rpo_idx[v]` = v 的 RPO 位置
  - `_dom_intersect(b1, b2)` — 沿 idom 链爬升直到 b1==b2，返回两节点在支配树中最近公共祖先
  - 固定点循环：对每个 RPO 非入口节点，对所有已确定 idom 的前驱取 intersect，有变化则 changed=1
  - `dom_idom[v]` — v 的直接支配节点（入口节点设为 -1）
  - 测试：5 顶点 CFG（0→1,0→2,1→3,2→3,3→4）→ idom=[−1,0,0,0,3]
  - Buffer: 0x1690000，DOM_MAX_V=16
  - Shell 命令：`dom add <u> <v>  dom run  dom idom <v>  dom setn <n>  dom test`

## Iteration 305 — virtual_tree.hl：虚树构造

- **`bare-kernel/hl/virtual_tree.hl`** 新增（~110 行）
  - 给定 k 个关键顶点，压缩建树（关键点 + 相邻对 LCA）O(k²)
  - 收集关键顶点 → 两两求 LCA 补充虚节点 → 按 lca_tin[] 排序 → O(k²) 确定父节点
  - `_vt_in_nodes(v)` — 去重；`_vt_sort_tin()` — 插入排序（done-flag 替代 break）
  - 父节点查找：对每个节点 v，遍历所有节点 w，若 `lca_query(v,w)==w` 则 w 是 v 的祖先，取深度最大者
  - `vt_par_of(v)` — 返回 v 在虚树中的父节点（-1=根）
  - 测试：7 节点树，关键点 {3,5,6} → nn=5，par(3)=1，par(5)=2，par(6)=2
  - Buffer: 0x1680000，VT_MAX_KEY=16，VT_MAX_NODE=32
  - Shell 命令：`vt add <v>  vt build  vt par <v>  vt test`

## Iteration 304 — lca.hl：最近公共祖先（倍增）

- **`bare-kernel/hl/lca.hl`** 新增（~100 行）
  - 倍增预处理 O(n log n)，查询 O(log n)；为 virtual_tree.hl 导出 lca_tin[]
  - `_lca_dfs(u, par)` — 记录 DFS 入时戳 tin、深度 depth、0 阶祖先 anc[][0]；根节点自环
  - `_lca_build_table()` — 倍增填表：`anc[v][k] = anc[anc[v][k-1]][k-1]`
  - `lca_query(u,v)` — 深度对齐（逐位提升）→ 同时提升两点至 LCA 下方 → 取 anc[][0]
  - LCA_MAX_V=32，LCA_LOG=5（支持最多 32 个节点深度 ≤ 32 的树）
  - 测试：7 节点完全二叉树，LCA(3,4)=1，LCA(3,6)=0，LCA(5,6)=2
  - Buffer: 0x1670000
  - Shell 命令：`lca add <u> <v>  lca run  lca query <u> <v>  lca setn <n>  lca test`

## Iteration 303 — heavy_light.hl：重链剖分（HLD）

- **`bare-kernel/hl/heavy_light.hl`** 新增（~120 行）
  - 标准 HLD：O(n) 构建，路径查询 O(log n) 次链跳，每次 O(链长) 区间求和
  - 两趟 DFS：`_hl_dfs1(u,par,d)` 计算 sz/par/depth/heavy 子节点；`_hl_dfs2(u,head)` 分配 pos/head/hl_arr
  - `hl_arr[pos]` — HLD 顺序值数组；heavy 子节点优先处理，延续当前链
  - `hld_path_sum(u,v)` — 两端不同链时，移动链头较深者并累加链和，最终两端同链时加剩余段
  - 测试：7 顶点树（chains: 0→1→3, 2→5→6, {4}），path_sum(3,6)=23
  - Buffer: 0x1660000，HL_MAX_V=32
  - Shell 命令：`hld add <u> <v>  hld run  hld sum <u> <v>  hld setval <v> <w>  hld setn <n>  hld test`

## Iteration 302 — centroid.hl：树重心分解

- **`bare-kernel/hl/centroid.hl`** 新增（~100 行）
  - Jordan 1869 / 竞赛标准：O(n log n) 树分治基础
  - `_cd_calc_size(u, par)` — 递归计算当前连通分量各顶点子树大小（已标记顶点视为屏障）
  - `_cd_find_centroid(u, par, tree_sz)` — 找到满足所有子分量 ≤ tree_sz/2 的重心
  - `_cd_decompose(u, par_cent)` — 找重心→标记删除→递归各邻域子分量
  - `cd_cent[v]` — 重心树中 v 的父重心（-1=根重心）；`cd_cent_count` = n 时分解完成
  - 测试：路径图 0-1-2-3-4 → 根重心=2，cd_cent=[1,2,-1,2,3]，count=5
  - Buffer: 0x1650000，CD_MAX_V=32
  - Shell 命令：`cen add <u> <v>  cen run  cen cent <v>  cen setn <n>  cen test`

## Iteration 301 — min_cost_flow.hl：最小费用最大流

- **`bare-kernel/hl/min_cost_flow.hl`** 新增（~115 行）
  - 逐次最短路法：SPFA 找最短增广路 + 回溯增广，O(VEf)
  - 边表 + 邻接链表（mcf_head/mcf_next）；`mcf_rev_e[e]` 存配对反向边索引（无需 XOR）
  - `_mcf_spfa(src, sink)` — Bellman-Ford 队列版；dist/in_q/prev_e 数组；非循环队列大小 256
  - `_mcf_augment(src, sink)` — 回溯 prev_e 找瓶颈→正反向更新残差→累计费用
  - `mcf_flow` — 总流量；`mcf_cost_total` — 总费用
  - 测试：5 边图（s=0, t=3）→ flow=5, cost=17
  - Buffer: 0x1640000，MCF_MAX_V=16，MCF_MAX_E=128
  - Shell 命令：`mcf add <u> <v> <cap> <cost>  mcf run <src> <sink>  mcf flow  mcf cost  mcf setn <n>  mcf test`

## Iteration 300 — hopcroft_karp.hl：Hopcroft-Karp 二部图最大匹配

- **`bare-kernel/hl/hopcroft_karp.hl`** 新增（~115 行）
  - Hopcroft-Karp 1973：O(E√V)，BFS 分层 + DFS 多路增广
  - `hk_adj[l*32+r]` — 左右邻接矩阵，HK_MAX_L=HK_MAX_R=32
  - `_hk_bfs()` — 从所有自由左顶点出发 BFS 建层次图；遇自由右顶点置 found=1
  - `_hk_dfs(u)` — DFS 沿层次图增广；回溯更新 match_l/match_r；未增广时设 dist=INF
  - `hopcroft_karp_run()` — 循环 BFS→DFS 直至无增广路
  - 测试：4L×4R 交叉边图 → perfect matching size=4
  - Buffer: 0x1630000
  - Shell 命令：`hk add <l> <r>  hk run  hk size  hk setnl <nl>  hk setnr <nr>  hk test`

## Iteration 299 — hungarian.hl：匈牙利算法（最优指派）

- **`bare-kernel/hl/hungarian.hl`** 新增（~120 行）
  - Kuhn-Munkres 1955：O(n³) 对偶势方法（Jonker-Volgenant 风格）
  - `hu_cost[(i+1)*17+(j+1)]` — 1-indexed n×n 代价矩阵，HU_MAX_N=16
  - `hu_u[i]`, `hu_v[j]` — 左右对偶势；`hu_p[j]` — 右顶点 j 配对的左顶点
  - `hungarian_run()` — 逐行处理：BFS-like 扫描更新 minv/way → delta 更新势 → 路径增广
  - `hu_match[i]` — 0-indexed 结果：左顶点 i 匹配的右顶点
  - 测试：4×4代价矩阵，最优指派 0→1,1→0,2→2,3→3 → min_cost=13
  - Buffer: 0x1620000
  - Shell 命令：`hu set <i> <j> <w>  hu run  hu cost  hu match <i>  hu setn <n>  hu test`

## Iteration 298 — two_sat.hl：2-SAT 可满足性求解

- **`bare-kernel/hl/two_sat.hl`** 新增（~110 行）
  - Aspvall-Plass-Tarjan 1979：O(V+E) 蕴含图 + Tarjan SCC
  - 文字节点编码：变量 i 真文字=2i，假文字=2i+1；`_ts_neg(v)` 求反（无 XOR，用奇偶判断）
  - 子句 (a OR b) → 添加边 neg(a)→b 和 neg(b)→a
  - SAT 充要条件：无变量与其否定同处一个 SCC
  - `ts_assign[i]` — 满足赋值：`scc[2i]>scc[2i+1]` 则 xi=true
  - 测试：3 变量，3 子句 → sat=1，给出一组满足赋值
  - Buffer: 0x1610000，TS_MAX_N=16
  - Shell 命令：`ts add <a> <b>  ts run  ts sat  ts assign <i>  ts setn <n>  ts test`

## Iteration 297 — euler_path.hl：Hierholzer 欧拉路径/回路

- **`bare-kernel/hl/euler_path.hl`** 新增（~115 行）
  - Hierholzer 1873：O(E) 迭代 DFS 回溯栈，路径末尾反转
  - `ep_adj[u*32+v]` — 边计数矩阵（支持多重边），EP_MAX_V=32
  - `_ep_check_and_start()` — 奇度数=0 → 欧拉回路（start=0）；奇度数=2 → 欧拉路径（start=奇度顶点）；否则无欧拉路径
  - 奇偶判断：`rem = ep_deg[i] - (ep_deg[i] / 2) * 2`（H-L 无 % 运算符）
  - `ep_run(start)` — 栈顶 v 有未用边→压入邻居；否则弹出并记录路径；最后反转
  - 测试：4 顶点回路 0-1,1-2,2-3,3-0 → is_circuit=1，path_n=5，path[0]=0，path[4]=0
  - Buffer: 0x1600000
  - Shell 命令：`ep add <u> <v>  ep run  ep path  ep setn <n>  ep test`

## Iteration 296 — articulation.hl：关节点与桥（Tarjan DFS）

- **`bare-kernel/hl/articulation.hl`** 新增（~115 行）
  - Tarjan 1974：O(V+E) DFS low-link 无向图关节点+桥同步检测
  - `art_adj[u*32+v]` — 无向邻接矩阵，ART_MAX_V=32
  - `_art_dfs(u, par)` — 树边：子节点 DFS 后更新 low；非根 AP 条件：`low[v]>=disc[u]`；桥条件：`low[v]>disc[u]`；回边跳过父节点
  - 根节点 AP 判断：DFS 子树数量 > 1（循环结束后检查）
  - `articulation_run()` — 重置状态，遍历所有未访问顶点，返回关节点数
  - 测试：0-1,1-2,2-3,1-3,3-4 → art_count=2（顶点 1,3），bridges=1（边 3-4）
  - Buffer: 0x15F0000
  - Shell 命令：`art add <u> <v>  art run  art count  art setn <n>  art test`

## Iteration 295 — tarjan.hl：Tarjan 强连通分量

- **`bare-kernel/hl/tarjan.hl`** 新增（~105 行）
  - Tarjan 1972：O(V+E) 递归 DFS disc/low-link，SCC 栈弹出
  - `tr_adj[u*32+v]` — 有向邻接矩阵，TR_MAX_V=32
  - `_tr_dfs(u)` — 设 disc/low，压栈 on_stack；树边递归更新 low；回边仅当 on_stack 时更新 low；`low[u]==disc[u]` 时弹出 SCC
  - `tr_scc[v]` — 顶点所属 SCC 编号（0-indexed）；`tr_scc_count` — SCC 总数
  - 测试：0→1,1→2,2→0,0→3,3→4 → scc_count=3（{0,1,2},{3},{4}）
  - Buffer: 0x15E0000
  - Shell 命令：`tr add <u> <v>  tr run  tr scc <v>  tr setn <n>  tr test`

## Iteration 294 — bipartite_match.hl：二部图最大匹配

- **`bare-kernel/hl/bipartite_match.hl`** 新增（~110 行）
  - 增广路 DFS 二部图最大匹配 O(VE)；支持递归重匹配链（Hopcroft-Karp 风格）
  - `bm_adj[l*32+r]` — 左右节点邻接矩阵，BM_MAX_L=32，BM_MAX_R=32
  - `_bm_dfs(l)` — 递归增广：若右节点 r 空闲直接匹配，否则递归重匹配已占 r 的左节点
  - `bm_run()` — 逐左节点 DFS，每次重置 bm_vis，累计 bm_size
  - 测试：L={0,1,2,3} R={0,1,2,3}，8条边 → 完美匹配 size=4
  - Buffer: 0x15D0000
  - Shell 命令：`bm add <l> <r>  bm run  bm size  bm setnl <nl>  bm test`

## Iteration 293 — max_flow.hl：Edmonds-Karp 最大流

- **`bare-kernel/hl/max_flow.hl`** 新增（~100 行）
  - Edmonds-Karp 1972：BFS 增广路 Ford-Fulkerson，O(VE²)
  - `mf_cap[u*16+v]` — 残差容量矩阵（正向容量 + 反向容量）；MF_MAX_V=16
  - `_mf_bfs(src, sink)` — BFS 找增广路，返回是否找到；mf_parent 记录路径
  - `mf_run(src, sink)` — 循环 BFS → 计瓶颈 → 正反向更新残差 → 累计 mf_flow
  - 测试：CLRS 经典 6 顶点流网络（s=0, t=5）→ max_flow=23
  - Buffer: 0x15C0000
  - Shell 命令：`mf add <u> <v> <c>  mf run <src> <sink>  mf flow  mf setn <n>  mf test`

## Iteration 292 — a_star.hl：A* 启发式搜索

- **`bare-kernel/hl/a_star.hl`** 新增（~115 行）
  - Hart-Nilsson-Raphael 1968：f(v)=g(v)+h(v)，线性扫描 open set O(V²)
  - `as_set_pos(v, x, y)` — 设置顶点 2D 坐标（Manhattan 距离启发函数）
  - `_as_h(v, dst)` — h = |hx[v]-hx[dst]| + |hy[v]-hy[dst]|，绝对值用 `0-dx` 模拟
  - `as_run(src, dst)` — 维护 open/closed 集合，每轮选 min-f 未闭合顶点展开邻居
  - 测试：5 顶点格点图，所有 0→4 路径均长 6 → cost=6
  - Buffer: 0x15B0000，AS_MAX_V=32
  - Shell 命令：`as add <u> <v> <w>  as setpos <v> <x> <y>  as run <src> <dst>  as setn <n>  as test`

## Iteration 291 — floyd_warshall.hl：Floyd-Warshall 全对最短路

- **`bare-kernel/hl/floyd_warshall.hl`** 新增（~110 行）
  - Roy-Floyd-Warshall 1962：O(V³) 三重循环 DP，支持负权边
  - `fw_add_edge(u, v, w)` — 有向边，多边取最小权，自动更新 fw_n
  - `fw_run()` — 三重循环 d[i][j]=min(d[i][j], d[i][k]+d[k][j])；外层 INF 保护避免溢出
  - `fw_neg_cycle` — fw_dist[i][i]<0 则置 1（负权环检测）
  - `fw_dist_q(u, v)` — 查询 u→v 距离，不可达返回 -1
  - 测试：4 顶点 0→1:3,0→3:7,1→0:8,1→2:2,2→0:5,2→3:1,3→0:2 → d[0][1]=3,d[0][2]=5,d[0][3]=6,d[1][0]=5,neg_cycle=0
  - Buffer: 0x15A0000，FW_MAX_V=16，FW_INF=1000000
  - Shell 命令：`fw add <u> <v> <w>  fw run  fw dist <u> <v>  fw setn <n>  fw test`

## Iteration 290 — kruskal.hl：Kruskal MST + DSU

- **`bare-kernel/hl/kruskal.hl`** 新增（~120 行）
  - Kruskal 1956：O(E log E) 边列表按权插入排序 + DSU 贪心合并
  - `_kr_find(x)` — 迭代路径压缩 DSU find；`_kr_union(a, b)` — 按秩合并，返回是否新合并
  - `kruskal_run()` — 插入排序边 → 逐边 _kr_union，合并则累计权重，kr_mst_edges < n-1 时停止
  - 测试：同 prim_test 5 顶点图 → mst_weight=16, mst_edges=4
  - Buffer: 0x1590000，KR_MAX_V=32，KR_MAX_E=128
  - Shell 命令：`kr add <u> <v> <w>  kr run  kr weight  kr setn <n>  kr test`

## Iteration 289 — prim.hl：Prim MST

- **`bare-kernel/hl/prim.hl`** 新增（~100 行）
  - Prim 1957：O(V²) 线性扫描最小 key 顶点，邻接矩阵，无向图
  - `prim_add_edge(u, v, w)` — 对称置邻接矩阵，自动更新 prim_n
  - `prim_run()` — 重置 key/parent/in_mst → 反复选 min-key 未访问顶点 u → 松弛邻居
  - `prim_mst_weight` — 运行后累计 MST 总权重
  - 测试：5 顶点图 0-1:2,0-3:6,1-2:3,1-3:8,1-4:5,2-4:7,3-4:9 → mst_weight=16（MST:0-1,1-2,1-4,0-3）
  - Buffer: 0x1580000，PRIM_MAX_V=32，PRIM_INF=1000000
  - Shell 命令：`prim add <u> <v> <w>  prim run  prim weight  prim setn <n>  prim test`

## Iteration 288 — bellman_ford.hl：Bellman-Ford 最短路 + 负权环检测

- **`bare-kernel/hl/bellman_ford.hl`** 新增（~115 行）
  - Bellman 1958 / Ford 1956：O(VE) 边列表松弛，支持负权边
  - `bf_add_edge(u, v, w)` — 边列表追加，自动更新 bf_n
  - `bf_run(src)` — V-1 轮完整松弛 + 第 V 轮检测负权环（bf_neg_cycle=1）
  - `bf_dist_v(v)` — 返回 bf_dist[v]，不可达返回 -1
  - 测试1：0→1:3, 0→2:6, 1→2:-2, 2→3:1 → d[1]=3, d[2]=1, d[3]=2, neg_cycle=0
  - 测试2：0→1:1, 1→2:-3, 2→0:1 → neg_cycle=1（负权回路正确检测）
  - Buffer: 0x1570000，BF_MAX_V=32，BF_MAX_E=128
  - Shell 命令：`bf add <u> <v> <w>  bf run <src>  bf dist <v>  bf setn <n>  bf negcycle  bf test`

## Iteration 287 — topological_sort.hl：Kahn BFS 拓扑排序 + 环检测

- **`bare-kernel/hl/topological_sort.hl`** 新增（~100 行）
  - Kahn 1962：O(V+E) 入度数组 + BFS 队列，基于邻接矩阵
  - `topo_add_edge(u, v)` — 邻接矩阵置 1，自动更新 topo_n
  - `topo_run()` — 从矩阵计算入度 → 零入度入队 → BFS 出队减入度 → 再入队
  - `topo_has_cycle` — order_n < n 则置 1（存在环）
  - 测试1：经典 DAG 5→2,5→0,4→0,4→1,2→3,3→1 → order_n=6, has_cycle=0
  - 测试2：0→1→2→0 环 → order_n=0, has_cycle=1
  - Buffer: 0x1560000，TOPO_MAX_V=32
  - Shell 命令：`topo add <u> <v>  topo run  topo order  topo cycle  topo setn <n>  topo test`

## Iteration 286 — dijkstra.hl：Dijkstra 单源最短路

- **`bare-kernel/hl/dijkstra.hl`** 新增（~125 行）
  - Dijkstra 1959：O(V²) 线性扫描最小未访问顶点，邻接矩阵存边
  - `dijkstra_add_edge(u, v, w)` — 有向边，自动更新 dijk_n；权重必须为正
  - `dijkstra_run(src)` — 重置距离数组 → 循环找 min 未访问 u → 松弛出边；u=-1 或 dist[u]≥INF 时提前退出
  - `dijkstra_dist(v)` — 返回 dist[v]，不可达返回 -1
  - 测试：5 顶点图 0→1:4,0→2:1,2→1:2,1→3:1,2→3:5,3→4:3 → d[1]=3, d[3]=4, d[4]=7
  - Buffer: 0x1550000，DIJK_MAX_V=32，DIJK_INF=1000000
  - Shell 命令：`dijk add <u> <v> <w>  dijk run <src>  dijk dist <v>  dijk setn <n>  dijk test`

## Iteration 285 — convex_hull.hl：凸包（Andrew 单调链）

- **`bare-kernel/hl/convex_hull.hl`** 新增（~115 行）
  - Andrew's Monotone Chain 1979：O(n log n)（插入排序）+ 单次扫描构建上/下包
  - `_ch_sort()` — 插入排序按 (x,y) 字典序升序
  - `_ch_cross3(ox,oy,ax,ay,bx,by)` — 有符号叉积：>0 左转，≤0 右转/共线
  - `ch_build()` — 先建下包（左→右，保 CCW），再建上包（右→左，k≥t 保护下包不被弹出）
  - 测试：5点 (0,0)(2,0)(2,2)(0,2)(1,1) → hull_n=4，内点(1,1)正确排除
  - Buffer: 0x1540000，CH_MAX_N=64
  - Shell 命令：`ch add <x> <y>  ch build  ch hull_n  ch test`

## Iteration 284 — lcs.hl：LCS + 编辑距离 + LIS

- **`bare-kernel/hl/lcs.hl`** 新增（~120 行）
  - **LCS**（最长公共子序列）O(nm)：标准 DP，dp[i][j]=dp[i-1][j-1]+1 或 max(up,left)
  - **Levenshtein 编辑距离** O(nm)：dp 初始化 dp[i][0]=i, dp[0][j]=j；三操作取 min
  - **LIS**（最长上升子序列）O(n²)：lis_dp[i] = 以 arr[i] 结尾的最长严格上升子序列长
  - 测试：LCS("ABCBDAB","BDCAB")=4；edit("kitten","sitting")=3；LIS([10,9,2,5,3,7,101,18])=4
  - Buffer: 0x1530000，LCS_MAX=32，LIS_MAX=128
  - Shell 命令：`lcs test`

## Iteration 283 — leftist_heap.hl：左偏堆（可合并优先队列）

- **`bare-kernel/hl/leftist_heap.hl`** 新增（~130 行）
  - Crane 1972 左偏堆：满足堆序 + 左偏性质（rank(left)≥rank(right)）
  - `_lh_merge(a, b)` — 递归合并：保证根更小，递归合并右脊，合并后修正左偏性质，更新 rank
  - O(log n) merge/insert/extract-min（右脊长度 = rank = O(log n)）
  - 支持双堆：lh_root（主堆）+ lh_root2（副堆），`lh_merge_heaps()` 合并为单堆
  - 测试：heap1=[5,3,8,1,4,7]，heap2=[2,6,9]，O(log n) 合并后顺序提取 → 1..9 升序
  - Buffer: 0x1520000，LH_MAX_NODES=64
  - Shell 命令：`lh insert <v>  lh insert2 <v>  lh extract  lh peek  lh merge  lh status  lh test`



- **`bare-kernel/hl/kd_tree.hl`** 新增（~175 行）
  - 2D KD-Tree：交替 x/y 轴中位数分割，O(n log n) 构建
  - `_kd_sort_range(start, end, axis)` — 插入排序对 kd_idx[start..end] 按轴坐标排序
  - `_kd_build(start, end, depth)` — 递归构建，节点池 1-based，depth mod 2 选轴
  - `kd_nearest(qx, qy)` — 最近邻：优先探索更近半空间，仅当 diff²<best_d² 才探索另一半
  - `kd_range_count(qx, qy, r2)` — 球范围计数：对比 split-plane 距离² 与 r² 决定双/单侧递归
  - 测试：6 点集，nearest(4,5)=(4,6) d²=1；range_r2=10 from (4,5) → 3 点
  - Buffer: 0x1510000，KD_MAX_N=32
  - Shell 命令：`kd add <x> <y>  kd build  kd nearest <x> <y>  kd range <x> <y> <r2>  kd status  kd test`

## Iteration 281 — binary_heap.hl：二叉堆 + 堆排序

- **`bare-kernel/hl/binary_heap.hl`** 新增（~130 行）
  - 二叉最小堆，0-indexed（root=0，parent=(i-1)/2，children=2i+1/2i+2）
  - `_bh_sift_up(i)` / `_bh_sift_down(i)` — done-flag 循环，O(log n)
  - `bh_insert` / `bh_extract_min` / `bh_peek` — 标准优先队列接口
  - `bh_heapify(arr, n)` — Floyd 建堆 O(n)：从最后内部节点向根 sift_down
  - `bh_heapsort(arr, n)` — 就地堆排序：先建最大堆，再逐步提取最大值，O(n log n)
  - 测试：insert [5,3,8,1,4,7,2,6] → extract 序列单调；heapsort [9,2,7,4,1,5] → [1,2,4,5,7,9]
  - Buffer: 0x1500000，BH_MAX_SIZE=128
  - Shell 命令：`bh insert <v>  bh extract  bh peek  bh heapsort <n>  bh status  bh test`

## Iteration 280 — sparse_table.hl：Sparse Table O(1) RMQ

- **`bare-kernel/hl/sparse_table.hl`** 新增（~90 行）
  - Sparse Table（Bender & Farach-Colton 2000），O(n log n) 构建，O(1) RMQ
  - `st_build(data, n)` — 双层循环：k=0 直接复制；k>0 从 k-1 合并 2^(k-1) 宽窗口
  - `st_rmq_min(l, r)` / `st_rmq_max(l, r)` — k=log2(r-l+1)，双端点重叠覆盖
  - st_log2[65] 预计算（递推：log2[i] = log2[i/2]+1），st_pow2[7] 预计算幂次
  - 测试：[3,1,4,1,5,9,2,6,5,3] → min(0,9)=1，max(0,9)=9，min(3,8)=1，max(4,7)=9
  - Buffer: 0x14F0000，ST_MAX_N=64，ST_LOG=7
  - Shell 命令：`st build <n>  st min <l> <r>  st max <l> <r>  st status  st test`



- **`bare-kernel/hl/interval_tree.hl`** 新增（~120 行）
  - 有序区间数组 + 后缀最大值 (suffix-max) 增强，支持 O(k) 期望查询（k=结果数）
  - `it_insert(lo, hi)` — 插入排序维护 lo 有序；每次插入后重建 suffix-max（O(n)）
  - `_it_rebuild_max()` — 反向一遍重建 it_max_suf[i] = max(hi[i..n-1])
  - `it_stab(q)` — 刺查询（点 q 落在哪些区间）：it_lo[i]>q 时终止；suffix-max<q 时提前退出
  - `it_overlap(qlo, qhi)` — 区间重叠查询：条件 it_lo[i]≤qhi AND it_hi[i]≥qlo
  - 测试：5 区间 [1,5][3,7][2,6][8,10][4,9] → stab(4)=4, overlap([5,8])=5, overlap([11,20])=0
  - Buffer: 0x14E0000
  - Shell 命令：`it insert <lo> <hi>  it stab <q>  it overlap <lo> <hi>  it status  it test`

## Iteration 278 — kmp.hl：KMP + Z函数 + Rabin-Karp

- **`bare-kernel/hl/kmp.hl`** 新增（~130 行）
  - **KMP**（Knuth-Morris-Pratt 1977）：失败函数构建 + 线性搜索，O(n+m)
    - 失败函数用 done-flag 内循环模拟 break；k 在迭代间持续
  - **Z函数**（Gusfield 1997）：z[i] = s 与 s[i..] 的最长公共前缀；标准双窗口 O(n)
    - z_search_count：构建 pat + [0] + text，Z值=|pat| 处即为匹配
  - **Rabin-Karp**（1987）：多项式哈希（base=31，mod=100003），rk_pow 预计算
    - 每窗口重新计算哈希（避免减法溢出问题）+ 字符验证消除假阳性
  - 测试：'ana' in 'banana' → kmp=2, z=2, rk=2（位置 1,3）
  - Buffer: 0x14D0000
  - Shell 命令：`kmp search  kmp z  kmp rk  kmp test`

## Iteration 277 — aho_corasick.hl：Aho-Corasick 多模式匹配

- **`bare-kernel/hl/aho_corasick.hl`** 新增（~155 行）
  - Aho & Corasick 1975：Trie + BFS 失败链接 + 完整 DFA，O(n + 匹配数) 搜索
  - `ac_ch[node*26+c]`：Trie 子节点；`ac_dfa[node*26+c]`：完整 DFA（构建后使用）
  - `ac_fail[]`：失败链接（指向最长真后缀）；`ac_dict[]`：字典后缀链接（最近完整词祖先）
  - `ac_build()`：BFS 两阶段 — 先处理根的子节点，再队列处理剩余节点
  - 测试：模式 "he"/"she"/"his"/"hers" in "ushers" → 3 次匹配（she@3, he@3, hers@5）
  - Buffer: 0x14C0000，AC_MAX_NODES=64，AC_ALPHA=26
  - Shell 命令：`ac init  ac build  ac search <text>  ac status  ac test`



- **`bare-kernel/hl/suffix_array.hl`** 新增（~215 行）
  - 后缀数组（Manber & Myers 1990，SIAM J. Computing）+ LCP 数组（Kasai et al. 2001）
  - 构建：前缀倍增法，O(n log²n)；每轮用插入排序对后缀对 (rank[i], rank[i+gap]) 排序
  - LCP：Kasai 线性算法，利用 "相邻后缀的 LCP 最多减少 1" 性质，O(n)
  - `sa_search_count(pat, plen)` — 二分搜索统计模式出现次数，O(m log n)
  - `sa_lrs()` — 最长重复子串长度 = max(LCP)
  - `sa_distinct_substrings()` — 不同子串数 = n(n+1)/2 - sum(LCP)
  - 测试：'banana' → SA=[5,3,1,0,4,2], LRS=3("ana"), distinct=15, count("ana")=2
  - Buffer: 0x14B0000
  - Shell 命令：`sa build <n>  sa lcp  sa lrs  sa distinct  sa search <p>  sa status  sa test`

## Iteration 275 — treap.hl：Treap（随机平衡 BST）

- **`bare-kernel/hl/treap.hl`** 新增（~190 行）
  - Treap（Seidel & Aragon 1996，Algorithmica）：BST（按键）+ 最大堆（按随机优先级）
  - Split/Merge 原语（递归实现），期望 O(log n) 所有操作
  - 子树大小追踪：`treap_rank(key)` 统计严格小于 key 的元素数；`treap_kth(k)` 第 k 小
  - `treap_insert/delete/search` + `treap_min/max`；池化节点分配（最多 TREAP_MAX_NODES=64）
  - Buffer: 0x14A0000
  - Shell 命令：`treap insert <k> <v>  treap delete <k>  treap search <k>  treap kth <k>  treap rank <k>  treap min/max  treap test`

## Iteration 274 — disjoint_set.hl：并查集（Union-Find）

- **`bare-kernel/hl/disjoint_set.hl`** 新增（~145 行）
  - Union-Find（Tarjan & van Leeuwen 1984，JACM），两大优化组合：路径压缩 + 按秩合并
  - 合并时间复杂度：O(α(n)) 摊还（α 为反 Ackermann 函数，实际近常数）
  - 每个连通分量维护：大小（dsu_sz）、最小元素（dsu_cmin）、最大元素（dsu_cmax）
  - `dsu_kruskal_mst(edges, num_edges)` — Kruskal 最小生成树（边需预排序）
  - Buffer: 0x1490000
  - Shell 命令：`dsu union <x> <y>  dsu find <x>  dsu connected <x> <y>  dsu size <x>  dsu status  dsu test`



## Iteration 273 — cuckoo_filter.hl：Cuckoo 过滤器

- **`bare-kernel/hl/cuckoo_filter.hl`** 新增（~240 行）
  - Cuckoo Filter（Fan, Andersen, Kaminsky, Mitzenmacher 2014），优于 Bloom 过滤器：**支持删除**
  - CF_BUCKETS=64 桶 × CF_BSIZE=4 槽 = 256 个指纹槽；8 位指纹，FPR ≈ 3.1%
  - 备用桶：h2 = h1 XOR hash(fp)（对称设计，支持重定位），XOR 通过逐位模拟实现
  - `cf_insert(item)` — 先尝试 h1/h2，满则 Cuckoo 踢出（最多 CF_MAX_KICKS=500 次）
  - `cf_contains(item)` — O(1) 查询（检查两个桶）
  - `cf_delete(item)` — O(1) 删除（Bloom 过滤器不支持）
  - Buffer: 0x1480000
  - Shell 命令：`cf insert <item>  cf contains <item>  cf delete <item>  cf status  cf test`

## Iteration 272 — segment_tree.hl：线段树

- **`bare-kernel/hl/segment_tree.hl`** 新增（~220 行）
  - 线段树（含懒惰传播），最大 SEG_MAX_N=128 元素，树节点数 4×128=512
  - 三棵并行树：sum/min/max 共享同一 lazy 数组（范围加操作）
  - `seg_build(data, n)` — 自底向上构建，O(n)
  - `seg_update_point(idx, val)` — 点更新（set），O(log n)
  - `seg_range_add(l, r, delta)` — 范围加（懒惰传播），O(log n)
  - `seg_query_sum/min/max(l, r)` — 范围查询，O(log n)
  - Buffer: 0x1470000
  - Shell 命令：`seg build <n>  seg update <i> <v>  seg range_add <l> <r> <d>  seg sum/min/max <l> <r>  seg test`

## Iteration 271 — fenwick_tree.hl：树状数组 (BIT)

- **`bare-kernel/hl/fenwick_tree.hl`** 新增（~180 行）
  - Fenwick Tree / BIT（Peter Fenwick 1994，Software: Practice and Experience）
  - 标准 BIT：`fenwick_update(i, delta)` 点加 + `fenwick_query(i)` 前缀和，O(log n)
  - 差分 BIT：`fenwick_range_update(l, r, delta)` 范围加 + `fenwick_point_query(i)` 点查，O(log n)
  - 二分提升：`fenwick_find_kth(k)` 查找第 k 个元素，O(log n)
  - 2D BIT：`fenwick_2d_update(r, c, delta)` + `fenwick_2d_query(r, c)` 矩形前缀和，O(log²n)
  - `_fw_lowbit(i)`：最低位 1 计算（H-L 无位运算，循环除 2 实现）
  - Buffer: 0x1460000
  - Shell 命令：`fw build <n>  fw update <i> <d>  fw query <i>  fw range <l> <r>  fw kth <k>  fw range_update  fw 2d_update  fw test`



## Iteration 270 — reservoir_sampling.hl：储层采样

- **`bare-kernel/hl/reservoir_sampling.hl`** 新增（~257 行）
  - 储层采样（Vitter 1985，TOMS Algorithm 970）+ 加权变体（Efraimidis & Spirakis 2006）
  - Algorithm R：从未知长度流中均匀随机采样 k 个元素，每项 O(1) 均摊
  - 加权采样：优先键 key_i = rand^(1/weight)，高权重项更可能被保留
  - Bernoulli 采样：每项以概率 p/1000 独立纳入样本
  - 分层采样：维护 RS_MAX_STRATA=8 个独立储层，保证按层比例表示
  - LCG 伪随机数生成器（Knuth 参数：a=1664525, c=1013904223）
  - Buffer: 0x1450000
  - Shell 命令：`rs add <item>  rs add_batch <n>  rs contains <x>  rs bern_init <p>  rs bern_add <item>  rs status  rs test`

## Iteration 269 — wavelet.hl：哈尔小波变换

- **`bare-kernel/hl/wavelet.hl`** 新增（~230 行）
  - Haar 小波变换（Alfred Haar 1909），固定点算术（WAVELET_SCALE=1000）
  - 1D 前向/逆向 DWT：O(n) 时间，多级分解（最多 WAVELET_MAX_LEVELS=6 级）
  - 2D DWT：行-列分解（适用于图像/矩阵压缩）
  - 阈值压缩：置零小系数，返回压缩率（非零系数占比）
  - Parseval 定理验证：能量保持（`energy_in ≈ energy_out`）
  - Buffer: 0x1440000
  - Shell 命令：`wv load <n>  wv forward <levels>  wv inverse <levels>  wv threshold <t>  wv info  wv test`

## Iteration 268 — tdigest.hl：t-Digest 分位数估计器

- **`bare-kernel/hl/tdigest.hl`** 新增（~247 行）
  - t-Digest（Ted Dunning & Otmar Ertl 2019），质心聚类在线分位数估计
  - 质心池 TD_MAX_CENTROIDS=128，压缩后保留 TD_COMPRESSION=50 个质心
  - 极值附近（q≈0/1）质心小 → 高精度；中位数附近质心大 → 均摊高效
  - `tdigest_quantile(q_times_1000)`：插值查询任意分位 q ∈ [0, 1000]，支持 p50/p90/p99/p99.9
  - `tdigest_merge`：合并两个 digest（跨节点合并再压缩）
  - `_td_k_limit`：k-scale 限制函数（简化线性版本）
  - Buffer: 0x1430000
  - Shell 命令：`td add <val>  td p50  td p90  td p99  td quantile <q>  td status  td test`



- **`bare-kernel/hl/merkle_tree.hl`** 新增（~290 行）
  - Merkle 树（Ralph Merkle 1987 / US Patent 4,309,569），加密哈希树
  - 最大 32 叶节点（MERKLE_MAX_LEAVES），完全二叉树（1-indexed 数组表示）
  - 哈希函数：FNV-1a 变体，`_merkle_hash_int(val)` 叶节点哈希，`_merkle_combine(left, right)` 父节点哈希
  - `merkle_build(leaf_data, count)` — 自底向上构建树，时间 O(n)
  - `merkle_update_leaf(leaf_idx, new_data)` — 单叶更新，仅重算受影响祖先路径 O(log n)
  - `merkle_get_proof(leaf_idx)` — 生成包含证明（Inclusion Proof）：返回兄弟节点哈希数组
  - `merkle_verify_proof(leaf_data, proof, depth, leaf_idx, root)` — 验证包含证明：从叶到根重算，O(log n)
  - `merkle_compare_roots(other_root)` — O(1) 根哈希比较，检测任意树差异
  - 容量自动对齐至 2 的幂次（`_merkle_next_pow2`），空叶填充哈希 0
  - Buffer: 0x1420000
  - Shell 命令：`merkle build <n>  merkle root  merkle proof <leaf>  merkle verify <data> <leaf>  merkle update <leaf> <val>  merkle test`

## Iteration 266 — lru_cache.hl：LRU 缓存

- **`bare-kernel/hl/lru_cache.hl`** 新增（~310 行）
  - LRU 缓存（O(1) get/put），双向链表 + 哈希表实现
  - 可配置容量（lru_capacity ≤ LRU_MAX_SIZE=64），32 桶开放寻址哈希表
  - 双向链表：Head ↔ [MRU] ↔ ... ↔ [LRU] ↔ Tail，头尾各一个哨兵节点
  - `lru_get(key)` — O(1)：哈希查找 + 移至 MRU 头部，统计命中率
  - `lru_put(key, val)` — O(1)：存在则更新+提升；新增则尾部驱逐 LRU 条目
  - `lru_peek(key)` — 查询不触发提升（不计入 LRU-K 访问次数）
  - `lru_invalidate(key)` — 主动删除指定键（用于缓存失效）
  - **LRU-K 变体**：`lru_k` 参数，仅在第 K 次访问后才提升至 MRU（频率感知驱逐）
  - 统计：hits / misses / evicts / hit_rate（per-mille）
  - Buffer: 0x1410000
  - Shell 命令：`lru get <key>  lru put <key> <val>  lru peek <key>  lru del <key>  lru status  lru test`

## Iteration 265 — count_min_sketch.hl：Count-Min Sketch 频率估计

- **`bare-kernel/hl/count_min_sketch.hl`** 新增（~260 行）
  - Count-Min Sketch（Cormode & Muthukrishnan 2005 / JACM），流式频率估计
  - w=64 列 × d=4 行计数器矩阵（256 个计数器），O(1) 更新和查询
  - 误差界：ε × ‖f‖₁，失败概率 δ ≤ e^(-d)，空间 O(w×d)
  - d 个独立哈希函数（不同乘法种子），`_cms_hash_int(key, j)` / `_cms_hash_str(s, j)`
  - `cms_add_int(key, count)` / `cms_add_str(s, count)` — 批量计数支持
  - `cms_query_int(key)` / `cms_query_str(s)` — 取 d 行最小值（保证不低估）
  - `cms_inner_product(other)` — 两个 Sketch 的内积估算（Σfₐ×fᵦ）
  - `cms_merge(other)` — 合并两个 Sketch（逐元素相加，适合分布式聚合）
  - `cms_track_hh(key, freq)` — 重尾检测（Heavy Hitters），维护 top-16 频繁项
  - Buffer: 0x1400000
  - Shell 命令：`cms add <key> <n>  cms query <key>  cms add_str <s> <n>  cms query_str <s>  cms status  cms test`

## Iteration 264 — consistent_hash.hl：一致性哈希环

- **`bare-kernel/hl/consistent_hash.hl`** 新增（~310 行）
  - 一致性哈希（Karger et al. 1997 / STOC），分布式负载均衡与最小重映射
  - 256 槽虚拟环（CHASH_RING_SIZE=256），最大 32 个物理节点（CHASH_MAX_NODES）
  - 每节点 3 个虚拟节点（CHASH_VNODES_PER_NODE），共 96 个虚拟节点（CHASH_MAX_VNODES）
  - 虚拟节点插入：`_chash_insert_vnode(pos, owner)` — 插入排序维护环有序
  - 键路由：`_chash_find_successor(h)` — 线性扫描找第一个 pos >= h 的活跃虚拟节点（环绕）
  - `chash_add_node(id, addr)` — 添加物理节点，自动分配 3 个虚拟节点到环
  - `chash_remove_node(id)` — 删除节点（标记虚拟节点为 inactive），键自动迁移至后继
  - `chash_get_node_str(key)` / `chash_get_node_int(key)` — 字符串/整数键路由，O(k)
  - `chash_get_replicas(key, r)` — 获取 r 个不同物理节点（副本路由）
  - 负载统计：`chash_load_counts` 记录每个物理节点处理的键数量
  - Hash 函数：djb2（字符串）/ 乘法散列（整数），无位运算，纯算术实现
  - Buffer: 0x13F0000
  - Shell 命令：`chash add <id> <addr>  chash remove <id>  chash get <key>  chash replicas <key> <r>  chash status  chash test`

## Iteration 263 — hyperloglog.hl：HyperLogLog 基数估计

- **`bare-kernel/hl/hyperloglog.hl`** 新增（~270 行）
  - HyperLogLog（Flajolet, Fusy, Gandouet, Meunier 2007），概率基数估计算法
  - m=64 寄存器（b=6 位索引），每寄存器存储最大前导零计数，误差率 ≈ 1.04/√64 ≈ 13%
  - `_hll_hash_int(key)` / `_hll_hash_str(s)` — FNV-1a 变体哈希，纯算术实现
  - `_hll_leading_zeros(w)` — 计算 26 位值的前导零数（逐位检测，无位运算）
  - `hll_add_int(key)` / `hll_add_str(s)` — 添加元素：低 b 位 → 寄存器索引，高位 → 前导零
  - `hll_estimate()` — 估算基数：α_m × m² × (Σ 2^(-M[j]))^(-1)
    - 小范围校正：零寄存器 > 0 时使用线性计数（linear counting）
    - α_64 = 0.7096（per-mille 整数 709）
  - `hll_merge(other_M)` — 合并另一个 HLL（逐寄存器取最大值）→ 联合基数估计
  - `hll_snapshot()` — 寄存器快照到 merge buffer
  - Buffer: 0x13E0000
  - Shell 命令：`hll add <item>  hll add_int <n>  hll estimate  hll merge  hll status  hll test`

## Iteration 262 — skiplist.hl：跳表有序映射

- **`bare-kernel/hl/skiplist.hl`** 新增（~280 行）
  - 跳表（William Pugh, 1990 / CACM），概率平衡有序链表结构
  - O(log n) 平均复杂度的插入、查找、删除，O(n) 顺序遍历
  - 最大 8 层（SKIP_MAX_LEVEL），最大 128 个节点（SKIP_MAX_NODES）
  - 整数键值对存储（key → value，支持更新）
  - 节点池（flat 数组）：skip_key / skip_val / skip_level / skip_forward（N × LEVEL）/ skip_free
  - `_skip_random_level()` — LCG 伪随机生成层高（p=0.5 逐层硬币翻转）
  - `skip_insert(key, val)` — 记录 update 路径，分配新节点并拼接各层前向指针
  - `skip_search(key)` — 从顶层逐层降落定位目标节点
  - `skip_delete(key)` — 摘除各层前向指针，自动收缩当前最大层
  - `skip_range(lo, hi)` — 范围扫描，返回区间内条目数
  - `skip_min()` / `skip_max()` — O(1) 最小值，O(k log n) 最大值
  - Buffer: 0x13D0000
  - Shell 命令：`skip insert <k> <v>  skip get <k>  skip delete <k>  skip range <lo> <hi>  skip status  skip test`

## Iteration 261 — crdt.hl：冲突自由可复制数据类型

- **`bare-kernel/hl/crdt.hl`** 新增（~410 行）
  - CRDTs（Shapiro et al. 2011 / INRIA Tech Report），分布式强一致合并语义
  - **G-Counter**（增长计数器）：每节点独立计数器，`gc_value()` = 所有节点之和，`gc_merge()` = 逐节点取最大值
  - **PN-Counter**（正负计数器）：双 G-Counter（P + N），`pn_value()` = sum(P) - sum(N)，支持递减
  - **G-Set**（增长集合）：仅插入，`gset_add()` 幂等，`gset_merge()` = union，无法删除
  - **2P-Set**（双相集合）：add-set + remove-set，元素一旦移除不可再添加，`tpset_contains()` 检查双集
  - **LWW-Element-Set**（最后写入胜出集合）：每元素维护 add-timestamp + remove-timestamp，`lww_contains()` = add_ts > rem_ts
  - **OR-Set**（可观察移除集合）：每次 add 生成唯一标签（node_id × 10000 + seq），remove 仅 tombstone 已观察标签，支持移除后重新添加
  - `crdt_init_all()` — 统一初始化所有 CRDT 结构
  - 最大 16 节点集群（CRDT_MAX_NODES），最大 64 元素（CRDT_MAX_ELEMS），最大 128 标签（CRDT_MAX_TAGS）
  - Buffer: 0x13C0000
  - Shell 命令：`crdt gc inc  crdt pn inc  crdt pn dec  crdt gset add <e>  crdt lww add <e>  crdt orset add <e>  crdt status  crdt test`

## Iteration 260 — bloom_filter.hl：布隆过滤器

- **`bare-kernel/hl/bloom_filter.hl`** 新增（~330 行）
  - 布隆过滤器（Burton Howard Bloom, 1970），概率集合成员查询
  - 256 位位数组（8 × 32 位整数，算术位模拟）
  - k 个独立哈希函数（FNV-1a 变体，纯算术实现，无位运算）
  - `bloom_add(item)` / `bloom_add_int(key)` — 字符串或整数键插入，O(k)
  - `bloom_query(item)` / `bloom_query_int(key)` — 成员查询（无假阴性，有界假阳性）
  - **计数布隆过滤器**：每位对应一个 4 位计数器，支持 `bloom_delete()` 删除操作
  - `bloom_popcount()` — 统计已设置位数（填充率估算）
  - `bloom_fp_rate()` — 假阳性率估算：(filled_bits/m)^k × 1000（整数 per-mille）
  - `bloom_union(other_bits)` — 两个过滤器取并集（OR 合并，纯算术位操作）
  - `bloom_needs_scale()` — 填充率超过 50% 时提示需要扩容
  - Buffer: 0x13B0000
  - Shell 命令：`bloom add <item>  bloom query <item>  bloom delete <item>  bloom status  bloom test`

## Iteration 259 — attention.hl：Transformer 自注意力机制

- **`bare-kernel/hl/attention.hl`** 新增（~350 行）
  - Transformer 核心模块（Vaswani et al. 2017 "Attention Is All You Need"）
  - 固定点算术：ATTN_SCALE=1000，最大序列长 32（ATTN_MAX_SEQ），模型维度 64（ATTN_MAX_DIM）
  - **缩放点积注意力**：`_attn_scaled_dot_product(Q, K, V, seq, dk, dv)` — softmax(QK^T / √d_k) × V
  - **多头注意力**：`attn_multihead_forward(input_seq, seq)` — Q/K/V 投影 + 注意力 + 输出投影 W_O
  - **正弦位置编码**：`_attn_precompute_pos_enc()` — 三角波近似 sin/cos，预计算缓存
  - **层归一化**：`attn_layer_norm(x, n)` — (x - mean) / sqrt(var + ε) × γ + β，整数平方根
  - **残差连接**：注意力输出和 FFN 输出均加上残差后做层归一化
  - **逐位置前馈层**：`attn_feedforward(x, dm)` — Linear→ReLU→Linear（两层 MLP）
  - 权重初始化：确定性伪随机（种子 = 位置索引 × 素数）
  - `attn_config(d_model, n_heads, d_ff)` — 配置模型参数并初始化权重
  - Buffer: 0x13A0000
  - Shell 命令：`attn config <dm> <heads> <dff>  attn forward <seq>  attn ffn  attn info  attn test`

## Iteration 258 — neural.hl：神经网络推理引擎

- **`bare-kernel/hl/neural.hl`** 新增（~410 行）
  - 多层感知机（MLP）前馈神经网络推理引擎
  - 固定点算术：NEURAL_SCALE=1000（3 位小数精度）
  - 最大 8 层（NN_MAX_LAYERS），每层最大 256 神经元（NN_MAX_NEURONS）
  - 权重存储：nn_weights[层 × NN_WEIGHT_SLAB]，nn_biases[层 × NN_MAX_NEURONS]
  - 激活函数：Linear / ReLU / Leaky-ReLU / Sigmoid / Tanh / Softmax（6 种）
  - `_nn_sigmoid(x)` — 分段线性近似：`0.5 + x/8`（|x| < 4 时）
  - `_nn_tanh(x)` — 多项式近似：`x - x³/3`（饱和裁剪 ±SCALE）
  - `_nn_softmax(values, count)` — 数值稳定版（减去 max，指数近似，归一化）
  - 权重初始化：`nn_xavier_init(layer)` 均匀分布 Xavier，`nn_he_init(layer)` He 初始化（适合 ReLU）
  - `nn_forward(input)` — 完整前向传播，激活值缓存于 nn_activations_cache
  - 损失函数：`nn_loss_mse(pred, target, n)` MSE，`nn_loss_cross_entropy(pred, target, n)` 交叉熵
  - `nn_argmax(output, n)` — 分类预测（最大激活值索引）
  - `nn_backward_output(target, output_size)` — 输出层梯度下降（权重 + 偏置更新）
  - Buffer: 0x1390000
  - Shell 命令：`nn layer <size> <act>  nn init  nn forward <inputs>  nn loss  nn train  nn info  nn test`

## Iteration 257 — matrix.hl：矩阵运算库

- **`bare-kernel/hl/matrix.hl`** 新增（~465 行）
  - 稠密矩阵运算库（类 BLAS），固定点算术（MATRIX_SCALE=1000）
  - 矩阵池：8 个槽位（MATRIX_POOL_SIZE），最大 16×16（MATRIX_MAX_SIZE=256）
  - `mat_alloc(rows, cols)` / `mat_free(m)` — 矩阵分配与释放
  - `mat_from_array(rows, cols, values)` / `mat_identity(n)` / `mat_copy(src)` — 创建操作
  - `mat_transpose(m)` — 转置（O(n²)）
  - `mat_add(a, b)` / `mat_sub(a, b)` / `mat_scale(m, scalar)` — 逐元素运算
  - `mat_mul(a, b)` — 标准 O(n³) 矩阵乘法（固定点除法）
  - `mat_hadamard(a, b)` — 逐元素（Hadamard）乘积
  - `mat_norm_frob(m)` — Frobenius 范数（整数开平方）
  - `mat_trace(m)` — 对角元素之和
  - `mat_lu_decompose(m)` — LU 分解，部分主元选取，原位运算
  - `mat_inverse(m)` — Gauss-Jordan 增广矩阵法求逆（O(n³)）
  - `mat_vecmul(m, x)` — 矩阵向量乘法 y = A × x
  - `mat_print(m, label)` — 截断打印（最多 4×4）
  - Buffer: 0x1380000
  - Shell 命令：`mat new <rows> <cols>  mat identity <n>  mat mul <a> <b>  mat inv <m>  mat norm <m>  mat info <m>  mat test`

## Iteration 256 — gossip.hl：SWIM Gossip 成员协议

- **`bare-kernel/hl/gossip.hl`** 新增（~430 行）
  - SWIM 协议（Das, Gupta, Karp 2002 / ICDCS）+ 流行病广播
  - 成员状态：ALIVE / SUSPECT / DEAD / LEFT
  - 11 种消息类型：PING / PING-REQ / ACK / ALIVE / SUSPECT / DEAD / JOIN / LEAVE / SYNC / SYNC_RESP / BROADCAST
  - 最大 64 成员（GOSSIP_MAX_MEMBERS），直接探测扇出 3（GOSSIP_FANOUT）
  - `gossip_init(node_id, addr)` — 初始化本节点，加入成员表
  - `gossip_join(seed_id, seed_addr)` — 通过种子节点加入集群
  - `_gossip_enqueue_event(type, id, inc)` — 事件入队，TTL = mult × log₂(N)（Retransmit 机制）
  - `gossip_build_ping(target)` — 构建带事件捎带的 PING 消息
  - `gossip_build_ping_req(target, via)` — 间接探测（PING-REQ）
  - `gossip_handle_ping()` / `gossip_handle_ack()` — 接收处理 + 事件合并
  - `gossip_suspect_member(id)` — 标记节点为 SUSPECT + 广播 SUSPECT 事件
  - `gossip_declare_dead(id)` — 宣告节点为 DEAD + 故障计数
  - `gossip_refute()` — 增加本节点 incarnation 以反驳误判
  - `gossip_tick(delta_ms)` — 推进探测定时器 + 怀疑超时（5000ms 后宣告 DEAD）
  - `gossip_broadcast(type, payload)` — 流行病广播至 k 个随机成员
  - Buffer: 0x1370000
  - Shell 命令：`gossip init <id> <addr>  gossip join <id> <addr>  gossip tick <ms>  gossip members  gossip status  gossip test`

## Iteration 255 — raft.hl：Raft 分布式共识

- **`bare-kernel/hl/raft.hl`** 新增（~400 行）
  - Raft 共识算法（Ongaro & Ousterhout 2014 / USENIX ATC'14）
  - 三种节点状态：Follower / Candidate / Leader
  - 领导者选举：`raft_start_election()` — 递增任期，向所有节点广播 RequestVote RPC
  - `raft_handle_request_vote()` — 投票逻辑：检查任期 + 日志最新性（Log Up-to-date）
  - `raft_handle_vote_response()` — 收集多数派选票后调用 `_raft_become_leader()`
  - 日志复制：`raft_propose(cmd)` — 客户端提交命令（仅 Leader 可接受）
  - `raft_build_append_entries(peer_idx)` — 构建 AppendEntries RPC（含 prevLogIndex/Term）
  - `raft_handle_append_entries()` — 追随者日志一致性检查 + 追加 + 更新 commitIndex
  - `raft_handle_append_response()` — 处理复制确认，调用 `_raft_advance_commit()`
  - 提交推进：`_raft_advance_commit()` — 统计多数派匹配索引，提升 commitIndex
  - 状态机应用：`_raft_apply_committed()` — 将已提交日志应用到状态机
  - 快照：`raft_install_snapshot()` — 安装压缩快照，丢弃旧日志
  - 选举定时器：`raft_tick(ms)` — 驱动超时（随机化选举超时 150-300ms，心跳 50ms）
  - 支持 7 节点集群，1024 条日志，64 条待处理
  - Shell 命令：`raft init <id> <size>  raft peer <id>  raft propose <cmd>  raft tick <ms>  raft status  raft test`

## Iteration 254 — jpeg.hl：JPEG 图像解码器

- **`bare-kernel/hl/jpeg.hl`** 新增（~350 行）
  - JPEG 基线解码器（ISO 10918-1 / ITU-T T.81）
  - 完整 JPEG 标记解析：SOI/EOI/SOF0/DHT/DQT/SOS/DRI/APP0/APP1/COM
  - `jpeg_decode(data)` — 扫描标记链，提取图像参数，生成像素数据
  - SOF0 解析：`_jpeg_parse_sof()` — 精度/宽/高/分量数
  - DQT 解析：`_jpeg_parse_dqt()` — 标准亮度/色度量化表，Zigzag 反扫描
  - 标准量化表：JPEG_LUMA_QT (64 系数) + JPEG_CHROMA_QT (64 系数)
  - Zigzag 扫描顺序：JPEG_ZIGZAG[64]（标准 8×8 DCT 系数顺序）
  - `_jpeg_idct_block(coeffs)` — AAN 算法近似 IDCT：行列两次 1D-IDCT 蝶形运算
  - 量化反变换：`_jpeg_dequantize(coeffs, qtable)` — 系数 × 量化步长
  - `_jpeg_ycbcr_to_rgb(Y, Cb, Cr, x, y)` — YCbCr→RGB 颜色空间转换（BT.601 系数）
  - `jpeg_get_pixel(x, y)` — 获取解码后 RGBA 像素
  - Shell 命令：`jpeg load <path>  jpeg info  jpeg pixel <x> <y>  jpeg idct  jpeg test`

## Iteration 253 — http2.hl：HTTP/2 协议

- **`bare-kernel/hl/http2.hl`** 新增（~380 行）
  - HTTP/2 协议（RFC 7540）+ HPACK 头部压缩（RFC 7541）
  - 10 种帧类型：DATA/HEADERS/PRIORITY/RST_STREAM/SETTINGS/PUSH_PROMISE/PING/GOAWAY/WINDOW_UPDATE/CONTINUATION
  - 14 种错误码（H2_ERR_*）+ 6 种 SETTINGS 参数
  - `h2_build_frame_header(len, type, flags, stream_id)` — 构建 9 字节帧头
  - `h2_parse_frame(data, pos)` — 解析入站帧，填充 h2_last_frame_* 状态
  - `h2_build_request(method, path, scheme, authority, sid)` — 构建 HEADERS 帧（HPACK 编码）
  - `h2_build_settings(ack)` — 构建 SETTINGS 帧（6 参数或 ACK）
  - `h2_build_ping(opaque, ack)` / `h2_build_goaway()` / `h2_build_window_update()` / `h2_build_rst_stream()`
  - HPACK 静态表：61 条预定义头部（:method GET/POST、:path /、:status 200/404 等）
  - HPACK 动态表：`h2_hpack_add_dynamic(name, val)` — 带 LRU 驱逐的动态头部表
  - HPACK 编码：索引引用（静态）+ 字面量增量索引（动态）
  - 流多路复用：128 流状态跟踪（idle/open/half-closed/closed）
  - 流量控制：`h2_build_window_update()` — 连接级 + 流级窗口更新
  - Shell 命令：`h2 connect  h2 get <p>  h2 post <p> <b>  h2 status  h2 stream <sid>  h2 ping  h2 goaway  h2 settings  h2 test`



- **`bare-kernel/hl/png.hl`** 新增（~400 行）
  - PNG 图像解码器（RFC 2083 / ISO 15948），RGBA 像素输出
  - 支持色彩类型：0(灰度)、2(RGB)、3(索引)、4(灰度+Alpha)、6(RGBA)
  - `png_decode(data)` — 解析 PNG 文件字节流，验证签名，处理 chunk 链
  - PNG 签名：8 字节（137 80 78 71 13 10 26 10）
  - Chunk 解析：IHDR（图像头）、IDAT（压缩像素）、PLTE（调色板）、tEXt（文本元数据）、IEND
  - IHDR 解析：宽/高/位深度/色彩类型/压缩方法/过滤方法/隔行扫描
  - DEFLATE 解压：原始存储块（type 00），LZ77 压缩块模拟
  - 过滤器重建：`_png_unfilter_row()` 支持 Filter 0-4（None/Sub/Up/Average/Paeth）
  - Paeth 预测器：`_png_paeth(a, b, c)` 标准实现
  - `png_get_pixel(x, y)` — 获取 RGBA 像素值（4 字节数组）
  - `png_show_ascii(cols, rows)` — ASCII Art 可视化（亮度映射到 @#8Oo+-. 字符）
  - Shell 命令：`png load <path>  png info  png pixel <x> <y>  png show  png test`

## Iteration 251 — grpc.hl：gRPC 协议

- **`bare-kernel/hl/grpc.hl`** 新增（~300 行）
  - gRPC 协议实现（gRPC Core Spec），HTTP/2 LPM 帧格式
  - 帧格式：5 字节头部（压缩标志 1B + 消息长度 4B 大端）
  - `grpc_encode_frame_header(msg_len)` — 编码 LPM 帧头
  - `grpc_decode_frame_header(header)` — 解码 LPM 帧头，返回 [compressed, length]
  - 服务注册：`grpc_register_service(name)` — 注册 gRPC 服务
  - 方法注册：`grpc_register_method(svc_idx, method)` — 注册方法，自动构建路径 /服务/方法
  - 支持最多 16 个服务 × 32 个方法（可扩展）
  - `grpc_call(method_path)` — 发起一元 RPC 调用（Unary RPC）
  - `grpc_server_handle(raw)` — 服务端：接收并路由帧化请求
  - 17 个 gRPC 状态码（0-16）：OK/CANCELLED/INVALID_ARGUMENT/NOT_FOUND/...
  - `grpc_set_metadata(key, val)` — 设置请求元数据头（最多 16 对）
  - `grpc_build_request_headers(path)` — 构建 HTTP/2 HEADERS 帧
  - `grpc_build_trailers(status)` — 构建响应 Trailers（grpc-status + grpc-message）
  - Shell 命令：`grpc svc <n>  grpc method <s> <m>  grpc call <p>  grpc list  grpc status  grpc meta <k> <v>  grpc test`

## Iteration 250 — x509.hl：X.509 证书解析器

- **`bare-kernel/hl/x509.hl`** 新增（~350 行）
  - X.509 v3 数字证书解析器（RFC 5280），支持 DER/PEM 格式
  - 用途：TLS 握手证书链验证、HTTPS 服务器身份认证
  - ASN.1 DER 解析：`_x509_read_tag`、`_x509_read_len`、`_x509_skip_element`
  - `x509_parse(der_data)` — 解析 DER 格式证书，提取所有关键字段
  - `x509_parse_pem(pem_str)` — 解析 PEM 格式证书（剥离 Base64 头尾并解码）
  - 字段提取：版本、序列号（十六进制）、颁发者 CN、主体 CN
  - 有效期：notBefore / notAfter（UTCTime 或 GeneralizedTime）
  - 公钥算法：RSA（OID 1.2.840.113549.1.1）/ EC / Ed25519
  - 公钥长度（bit）从 BIT STRING 长度推算
  - `_x509_parse_oid(data, pos)` — 解析 OID 点分十进制（ISO 8825-1）
  - `_x509_parse_dn(data, pos, end)` — 提取 Distinguished Name CN 属性
  - 最多同时保存 8 个证书（`X509_MAX_CERTS=8`）
  - Shell 命令：`x509 pem <d>  x509 list  x509 info <n>  x509 subject <n>  x509 issuer <n>  x509 key <n>  x509 clear  x509 test`



- **`bare-kernel/hl/chacha20_poly1305.hl`** 新增（~350 行）
  - ChaCha20-Poly1305 认证加密（RFC 8439），移动端优选 AEAD 方案
  - 用途：TLS 1.3（首选套件）、WireGuard、QUIC、无 AES 硬件加速设备
  - `chacha20_poly1305_set_key(key)` — 设置 256 位密钥（32 字节）
  - `chacha20_poly1305_set_nonce(nonce)` — 设置 96 位随机数（12 字节）
  - `chacha20_poly1305_set_aad(aad)` — 设置附加认证数据（AAD）
  - `chacha20_poly1305_encrypt(plaintext)` — 加密并生成 128 位 Poly1305 认证标签
  - OTK 派生：ChaCha20 计数器 0 的前 32 字节作为 Poly1305 一次性密钥
  - 加密：ChaCha20 计数器 1 起始的密钥流与明文异或
  - MAC 输入：pad(AAD) || pad(ciphertext) || len(AAD) || len(CT)
  - `chacha20_poly1305_decrypt(ciphertext)` — 解密并验证认证标签
  - `chacha20_poly1305_get_tag()` — 返回十六进制认证标签
  - `chacha20_poly1305_test()` — RFC 8439 §2.8.2 测试向量验证
  - Shell 命令：`cp1305 key <k>  cp1305 nonce <n>  cp1305 encrypt <data>  cp1305 tag  cp1305 test`

## Iteration 248 — aes_gcm.hl：AES-GCM 认证加密

- **`bare-kernel/hl/aes_gcm.hl`** 新增（~320 行）
  - AES-128-GCM 认证加密（NIST SP 800-38D / RFC 5116）
  - 用途：HTTPS/TLS 1.3、SSH、IPsec、安全通信的标准 AEAD 方案
  - `aes_gcm_set_key(key)` — 设置 128 位密钥（16 字节），计算哈希子密钥 H
  - `aes_gcm_set_nonce(nonce)` — 设置 96 位随机数（推荐长度）
  - `aes_gcm_set_aad(aad)` — 设置附加认证数据
  - `aes_gcm_encrypt(plaintext)` — CTR 模式加密 + GHASH 认证标签
  - GHASH：GF(2^128) 域乘法，生成 128 位认证标签
  - CTR 模式：J0 = nonce || 0x00000001，计数器从 2 起始
  - 标签：GHASH(H, AAD, CT) ⊕ AES_K(J0)
  - `aes_gcm_decrypt(ciphertext)` — CTR 解密（对称操作）
  - `aes_gcm_get_tag()` — 返回十六进制认证标签（32 hex 字符）
  - `aes_gcm_test()` — 标准测试向量验证
  - Shell 命令：`aesgcm key <k>  aesgcm nonce <n>  aesgcm aad <d>  aesgcm encrypt <d>  aesgcm tag  aesgcm test`

## Iteration 247 — curve25519.hl：X25519 ECDH 密钥交换

- **`bare-kernel/hl/curve25519.hl`** 新增（~280 行）
  - Curve25519 椭圆曲线 Diffie-Hellman（RFC 7748）
  - 曲线方程：y² = x³ + 486662x² + x（Montgomery 曲线，GF(2²⁵⁵ - 19)）
  - 用途：TLS 1.3 握手密钥交换、WireGuard、Signal 协议
  - `curve25519_set_scalar(bytes)` — 设置 32 字节私钥（自动 RFC 7748 标量 clamping）
  - Clamping：scalar[0] &= 248，scalar[31] &= 127，scalar[31] |= 64
  - `curve25519_get_public()` — 计算公钥 = scalar × G（G = 基点 u=9）
  - `curve25519_shared_secret(peer_pub)` — 计算共享密钥 = scalar × peer_pub
  - Montgomery 阶梯：恒定时间椭圆曲线标量乘法算法
  - 域算术：GF(2²⁵⁵ - 19) 上的加减乘法（算术运算模拟）
  - `curve25519_get_public_hex()` — 公钥十六进制字符串
  - `curve25519_get_shared_hex()` — 共享密钥十六进制字符串
  - `curve25519_test()` — 使用标准测试向量验证
  - Shell 命令：`curve25519 scalar <k>  curve25519 pubkey  curve25519 shared <p>  curve25519 pubhex  curve25519 test`



- **`bare-kernel/hl/sm4.hl`** 新增（~320 行）
  - SM4 分组密码（中国国家标准 GB/T 32907-2016）
  - 注：简化实现，使用简化 S-box 和密钥扩展（真实 SM4 使用固定 S-box 和 FK/CK 常量）
  - 用途：对称加密，中国商用密码标准，广泛用于金融、政务、电信
  - `sm4_set_key(key)` — 设置 128 位密钥（16 字节）
  - 密钥扩展：生成 32 个轮密钥（简化版本）
  - 轮密钥生成：K[i] = transformation(K[i-4] + K[i-3] + K[i-2] + K[i-1] + i×常数)
  - `sm4_encrypt_block(plaintext)` — 加密单个 128 位块（16 字节）
  - `sm4_decrypt_block(ciphertext)` — 解密单个 128 位块
  - SM4 结构：32 轮 Feistel 网络（非平衡 Feistel）
  - 状态：4 个 32 位字（X0, X1, X2, X3）
  - 轮函数：F(X0, X1, X2, X3, rk[i]) = X0 ⊕ T(X1 ⊕ X2 ⊕ X3 ⊕ rk[i])
  - T 变换 = L(τ(input))：τ 是非线性变换（S-box），L 是线性变换
  - `_sm4_tau(word)` — τ变换：4 字节并行 S-box 查表
  - S-box：8×8 置换表（简化版使用仿射变换生成）
  - `_sm4_l(word)` — L 变换：循环移位和异或（简化版）
  - 真实 L：word ⊕ (word<<<2) ⊕ (word<<<10) ⊕ (word<<<18) ⊕ (word<<<24)
  - 解密：使用反向轮密钥顺序（rk[31] → rk[0]）
  - 块大小：128 位（16 字节），密钥大小：128 位
  - SM4 优势：国密算法，自主可控，硬件加速广泛，与 AES 安全性相当
  - SM4_BUF=0x12D0000（19660800），512 KB 工作缓冲区（轮密钥 + S-box + 临时状态）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`sm4_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `sm4 key <key>` / `sm4 encrypt <data>` / `sm4 decrypt <data>` / `sm4 hex` / `sm4 test`

## Iteration 245 — sm3.hl：SM3 密码哈希

- **`bare-kernel/hl/sm3.hl`** 新增（~310 行）
  - SM3 密码哈希函数（中国国家标准 GB/T 32905-2016）
  - 注：简化实现，16 轮压缩（真实 SM3 使用 64 轮），简化消息扩展
  - 用途：数字签名、消息认证、随机数生成，中国商用密码标准哈希
  - `sm3_hash(data, len)` — 计算 SM3 哈希（256 位/32 字节）
  - 初始值（IV）：8 个 32 位常量（0x7380166f, 0x4914b2b9, ...）
  - 消息扩展：W[0-15] 直接来自消息块，W[16-67] 由扩展函数生成
  - 扩展函数（简化）：W[i] = W[i-16] + W[i-13] + W[i-8] + W[i-3]
  - 真实扩展：W[i] = P1(W[i-16] ⊕ W[i-9] ⊕ (W[i-3]<<<15)) ⊕ (W[i-13]<<<7) ⊕ W[i-6]
  - W'[i] = W[i] ⊕ W[i+4]（用于压缩函数）
  - `_sm3_process_block(block)` — 处理 512 位块（64 字节）
  - 压缩函数：32 轮（简化为 16 轮），每轮更新 8 个状态字（A-H）
  - 轮函数（简化）：temp1 = A + E + W[i]; temp2 = B + F + W'[i]; ...
  - 真实轮函数：SS1 = ((A<<<12) + E + (T[j]<<<j))<<<7; SS2 = SS1 ⊕ (A<<<12); TT1 = FF[j] + D + SS2 + W'[j]; ...
  - 布尔函数：FF（前 16 轮和后 48 轮不同）、GG（同样分段）
  - 置换函数：P0、P1（用于消息扩展）
  - 填充：与 SHA-256 类似，追加 1 bit + 0 padding + 64-bit 长度
  - 输出：8 个 32 位字的串联（256 位）
  - SM3 特点：国密算法，结构类似 SHA-256 但有创新（如消息扩展），抗碰撞/原像/第二原像攻击
  - SM3_BUF=0x12C0000（19595264），512 KB 工作缓冲区（状态 + 消息扩展 + W'数组）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`sm3_init()`
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `sm3 hash <data>` / `sm3 hex` / `sm3 test`

## Iteration 244 — brotli.hl：Brotli 压缩算法

- **`bare-kernel/hl/brotli.hl`** 新增（~300 行）
  - Brotli 压缩算法（Google 开发，RFC 7932）
  - 注：简化实现，窗口 4KB（真实 Brotli 最大 16MB），不支持静态字典和完整 Huffman
  - 用途：HTTP 内容编码，压缩比优于 gzip，速度快于 LZMA，Chrome/Firefox 原生支持
  - `brotli_compress(data, len)` — 压缩：写入流头 + LZ77 编码块 + 结束标记
  - 流头部：窗口大小（WBITS，4 位）+ 元数据（简化为 1 字节）
  - WBITS=10 表示窗口 2^10=1024 字节（简化，真实范围 10-24）
  - `_brotli_compress_block(data, len)` — 块压缩：LZ77 匹配 + 字面量/复制命令
  - 命令类型：INSERT_ONLY（纯字面量）、INSERT_COPY（距离-长度对）
  - INSERT_COPY 编码：cmd_byte + distance(2 字节) + length(1 字节)
  - 最小匹配长度：4 字节，最大：64 字节
  - 最大回溯距离：4096 字节（BROTLI_MAX_DISTANCE）
  - `_brotli_find_match(data, pos, len)` — 哈希表匹配：3 字节哈希 → 2048 槽位
  - 哈希函数：(b0×256 + b1×16 + b2) % 2048
  - `brotli_decompress(data, len)` — 解压：解析命令 → 还原字面量/复制
  - 复制操作：允许重叠复制（用于重复模式）
  - `brotli_set_quality(quality)` — 设置压缩质量（0-9，简化版，真实支持 0-11）
  - Brotli 优势：更好的压缩比（比 gzip 小 20-26%），流式压缩，预定义字典（13000+ 常用词）
  - 应用场景：Web 字体、网页资源、API 响应、CDN 内容分发
  - BROTLI_BUF=0x12B0000（19529728），512 KB 工作缓冲区（字典 + 哈希表 + 输出）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`brotli_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `brotli compress <data>` / `brotli decompress <data>` / `brotli quality <n>` / `brotli ratio <orig>` / `brotli test`

## Iteration 243 — zstd.hl：Zstandard 现代压缩

- **`bare-kernel/hl/zstd.hl`** 新增（~330 行）
  - Zstandard（zstd）现代压缩算法（Facebook/Meta 开发）
  - 注：简化实现，窗口 8KB（真实 zstd 支持更大窗口），仅支持 RAW/RLE/COMPRESSED 块类型
  - 用途：高压缩比 + 快速解压，优于 gzip，广泛用于生产环境（Linux 内核、数据库）
  - `zstd_compress(data, len)` — 压缩：写入帧头（魔数 0xFD2FB528 + 描述符）+ 压缩块
  - 魔数：4 字节 little-endian 0x28B52FFD（简化为近似值）
  - 帧描述符：简化为单字节（标志位：内容大小/单段/校验和/字典ID）
  - `_zstd_compress_block(output, pos, data, offset, size, is_last)` — 单块压缩：RLE/LZ77/RAW 自动选择
  - 块类型选择：全相同字节 → RLE，LZ77 有效 → 压缩，否则 → 原始
  - 块头部：3 字节（Last_Block 标志 + Block_Type + Block_Size）
  - RLE 块：块头 + 单个重复字节
  - 压缩块：块头 + LZ77 编码数据（字面量/匹配对）
  - 原始块：块头 + 未压缩数据
  - `_zstd_lz77_compress(data, offset, len, output)` — LZ77 压缩核心：滑动窗口匹配
  - 匹配最小长度：3 字节，最大长度：64 字节
  - 偏移量编码：简化版本，2 字节存储（真实 zstd 使用更复杂的偏移量编码）
  - `_zstd_find_match(data, base_offset, pos, len)` — 查找匹配：回溯 8192 字节窗口
  - `zstd_decompress(data, len)` — 解压：验证魔数 → 解析块 → 还原数据
  - 解压支持：RAW（直接复制）、RLE（重复字节）、COMPRESSED（简化版）
  - `zstd_set_level(level)` — 设置压缩级别（1-9，简化版，真实支持 1-22）
  - ZSTD_BUF=0x12A0000（19464192），256 KB 工作缓冲区（字典/窗口/输出）
  - Zstandard 优势：压缩比接近 LZMA，速度接近 LZ4，可训练字典，流式压缩
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`zstd_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `zstd compress <data>` / `zstd decompress <data>` / `zstd level <n>` / `zstd ratio <orig>` / `zstd test`

## Iteration 242 — siphash.hl：SipHash 防 DoS 哈希

- **`bare-kernel/hl/siphash.hl`** 新增（~280 行）
  - SipHash-2-4 防 DoS 哈希函数（2 压缩轮，4 最终化轮）
  - 注：简化实现，使用 32 位算术模拟 64 位操作，受 H-L 语言限制
  - 用途：哈希表键哈希，防止哈希洪水 DoS 攻击（HashDoS），安全但快速
  - `siphash_set_key(key)` — 设置 128 位密钥（16 字节）：k0 + k1
  - `siphash(data, len)` — 哈希数据：初始化 4 个 64 位状态 → 处理 8 字节块 → 最终化
  - 状态初始化：v0 = k0 ^ 0x736f6d65, v1 = k1 ^ 0x646f7261, v2 = k0 ^ 0x6c796765, v3 = k1 ^ 0x6e657261
  - `_siphash_compress(m)` — 压缩单个 8 字节块：v3 += m → 2 轮 SipRound → v0 += m
  - `_siphash_sipround()` — SipRound：4 个状态字的加法/旋转/异或混合
  - SipRound 操作：v0+=v1; v1=ROTL(v1,13); v1^=v0; v0=ROTL(v0,32); 等
  - 旋转位数：13, 16, 17, 21（ARX 结构：加法/旋转/异或）
  - 最终化：v2 ^= 0xff → 4 轮 SipRound → 输出 v0^v1^v2^v3
  - 长度编码：最后一块包含消息长度字节（在高位）
  - SipHash 安全性：需要密钥，不可预测，抗差分/线性攻击
  - 应用场景：Rust HashMap、Python dict（≥3.4）、Redis、FreeBSD 内核
  - SIPHASH_BUF=0x1290000（19398656），128 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`siphash_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `siphash key <key>` / `siphash hash <data>` / `siphash hex` / `siphash result` / `siphash test`

## Iteration 241 — xxhash.hl：xxHash 快速非加密哈希

- **`bare-kernel/hl/xxhash.hl`** 新增（~290 行）
  - xxHash32/xxHash64 超快非加密哈希算法
  - 注：简化实现，xxHash64 使用两个 xxHash32 组合（真实版本是真 64 位算术）
  - 用途：校验和、哈希表、文件完整性验证（非安全场景），速度极快（>10 GB/s）
  - `xxhash32(data, len)` — 计算 32 位哈希：分块处理 + 最终混淆
  - xxHash32 常量：5 个质数（PRIME1-5），用于状态混合
  - 大输入路径（≥16 字节）：4 个累加器（v1-v4），每次处理 16 字节（4×4）
  - `_xxhash_round32(acc, input)` — 单轮更新：acc = (acc + input×PRIME2) ×PRIME1 ← ROTL13
  - 合并累加器：ROTL(v1,1) + ROTL(v2,7) + ROTL(v3,12) + ROTL(v4,18)
  - 小输入路径（<16 字节）：seed + PRIME5 + length → 逐字节混合
  - `_xxhash_avalanche32(hash)` — 最终混淆（avalanche）：多次移位/乘法/异或
  - Avalanche 操作：hash ^= (hash>>15); hash ×= PRIME2; hash ^= (hash>>13); 等
  - `xxhash64(data, len)` — 简化 64 位哈希：两个不同种子的 xxHash32 组合
  - `xxhash_set_seed(seed)` — 设置种子（相同数据 + 不同种子 = 不同哈希）
  - `xxhash_benchmark(data, len, iterations)` — 性能测试辅助函数
  - xxHash 优势：极快速度（接近内存带宽），良好分布性，确定性，无加密开销
  - 应用场景：LZ4/Zstd 内部校验和、RocksDB、npm、dpkg
  - XXHASH_BUF=0x1280000（19333120），256 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`xxhash_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `xxhash seed <n>` / `xxhash hash <data>` / `xxhash64 <data>` / `xxhash hex` / `xxhash test`

## Iteration 240 — poly1305.hl：Poly1305 消息认证码

- **`bare-kernel/hl/poly1305.hl`** 新增（~280 行）
  - Poly1305 一次性 MAC（Message Authentication Code）
  - 注：简化实现，完整精度需要 130 位算术（模 2^130-5）
  - 用途：消息认证，常与 ChaCha20 配对形成 ChaCha20-Poly1305 认证加密
  - `poly1305_set_key(key)` — 设置 32 字节密钥：r（16 字节，带钳位）+ s（16 字节）
  - 钳位（clamping）：r 的特定位清零以避免弱密钥
  - `poly1305_update(data, len)` — 更新消息：按 16 字节块处理
  - `_poly1305_process_block(data, offset, block_len, is_final)` — 处理单块：添加填充 + 累加 + 乘法
  - 填充：每块添加 0x01 字节（Poly1305 规范）
  - `_poly1305_add(acc, block, len)` — 累加器加法：多精度加法 + 模约简
  - `_poly1305_multiply(acc, r)` — 累加器乘法：acc = (acc * r) mod (2^130-5)
  - `_poly1305_reduce(acc)` — 模约简：简化版本，确保 acc < 2^130
  - `poly1305_finalize()` — 生成 16 字节标签：acc + s
  - `poly1305_verify(expected_tag)` — 恒定时间标签比较
  - `poly1305_reset()` — 重置状态以重新计算
  - Poly1305 安全性：一次性（每个密钥只能用一次），16 字节标签
  - 算法流程：累加器初始化为 0 → 处理每个块（加 + 乘 r + 约简）→ 加 s → 输出标签
  - POLY1305_BUF=0x1270000（19398656），512 KB 工作缓冲区（r/s/累加器/乘法中间态）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`poly1305_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `poly1305 key <key>` / `poly1305 update <msg>` / `poly1305 tag` / `poly1305 verify <tag>` / `poly1305 test`

## Iteration 239 — argon2.hl：Argon2 密码哈希

- **`bare-kernel/hl/argon2.hl`** 新增（~280 行）
  - Argon2id 密码哈希函数（PHC 密码哈希竞赛冠军）
  - 注：简化实现，64 块（真实建议 ≥1024 块），3 次迭代
  - 用途：密码存储，抵御 GPU/ASIC/侧信道攻击，优于 bcrypt/scrypt
  - `argon2_hash(password, salt)` — 哈希密码：初始化内存 → 填充 → 提取
  - 支持三种变体：Argon2d（数据依赖，抗 GPU）、Argon2i（数据独立，抗侧信道）、Argon2id（混合，推荐）
  - `_argon2_init_memory(password, pwd_len, salt, salt_len, num_blocks)` — 初始化 64 个内存块
  - 每个块：64 字节（简化，真实 Argon2 使用 1024 字节）
  - `_argon2_fill_memory(num_blocks, pass)` — 填充阶段：多次迭代混合内存块
  - Argon2id 混合策略：第一遍使用 Argon2i（计数器伪随机），后续使用 Argon2d（数据依赖）
  - `_argon2_mix_blocks(target_idx, ref_idx, num_blocks)` — 混合两个块：XOR + 旋转
  - 引用块选择：Argon2i 使用伪随机函数，Argon2d 使用前一块数据
  - `_argon2_hash_block(password, pwd_len, salt, salt_len, block_index)` — 生成初始块：BLAKE2 风格哈希
  - `_argon2_finalize(num_blocks)` — 提取最终哈希：XOR 所有块
  - `argon2_set_variant(variant)` — 设置变体（0=d, 1=i, 2=id）
  - `argon2_set_time_cost(t)` — 设置时间成本（迭代次数，1-10）
  - 参数：内存成本=1024 KB（简化），时间成本=3，并行度=1
  - 输出：32 字节哈希（可配置）
  - ARGON2_BUF=0x1260000（19333120），256 KB 工作缓冲区（内存块 + 临时缓冲）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`argon2_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `argon2 hash <pwd> <salt>` / `argon2 variant <id>` / `argon2 cost <n>` / `argon2 hex` / `argon2 test`

## Iteration 238 — snappy.hl：Snappy 快速压缩

- **`bare-kernel/hl/snappy.hl`** 新增（~280 行）
  - Snappy 快速压缩算法（Google 开发）
  - 注：简化实现，哈希表大小 4096（真实 Snappy 更大），受内存限制
  - 用途：速度优先的压缩，低延迟场景（数据库、网络传输），压缩比次于 zlib
  - `snappy_compress(data, len)` — 压缩：写入原长度（varint）+ LZ77 压缩数据
  - `_snappy_compress_fragment(data, len)` — 核心压缩：哈希表匹配 + 字面量/复制操作码
  - LZ77 匹配：滑动窗口最多回溯 32768 字节，最小匹配 4 字节，最大匹配 64 字节
  - `_snappy_find_match(data, pos, len)` — 哈希查找匹配：4 字节哈希 → 候选位置 → 扩展匹配
  - `_snappy_hash_bytes(data, pos)` — 4 字节哈希函数：(b0+b1*256+b2*65536+b3*16777216) % 4096
  - `_snappy_emit_literal(output, pos, data, start, len)` — 发出字面量：标签（长度-1）+ 原始字节
  - `_snappy_emit_copy(output, pos, offset, len)` — 发出复制：标签（类型+长度）+ 偏移量（2 字节）
  - Snappy 操作码：LITERAL（直接字节）、COPY_1（2 字节偏移）、COPY_2（3 字节偏移）、COPY_4（4 字节偏移）
  - `snappy_decompress(data, len)` — 解压：读取原长度 + 解析操作码 + 还原数据
  - 复制操作：从已解压数据中复制（允许重叠复制以表示重复模式）
  - `_snappy_write_varint(buf, pos, value)` — 写入 varint：base-128 编码，MSB 表示是否继续
  - `_snappy_read_varint(buf, start_pos)` — 读取 varint：解码 base-128
  - 哈希表：4096 个槽位，存储位置索引用于快速匹配
  - SNAPPY_BUF=0x1250000（19267584），1 MB 工作缓冲区（哈希表 + 输入/输出缓冲）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`snappy_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `snappy compress <data>` / `snappy decompress <data>` / `snappy output` / `snappy len` / `snappy test`

## Iteration 237 — blake2.hl：BLAKE2 哈希函数

- **`bare-kernel/hl/blake2.hl`** 新增（~280 行）
  - BLAKE2 现代加密哈希函数（SHA-3 竞赛决赛选手）
  - 注：简化实现，受 H-L 语言约束（模拟位运算）
  - 用途：快速加密哈希，比 MD5/SHA-1 更安全，比 SHA-256 更快
  - `blake2_hash_data(data, len)` — 计算 BLAKE2b-256 哈希（32 字节）
  - `_blake2_init_state(digest_size)` — 初始化状态：8 个 IV 常量 XOR 参数块
  - `_blake2_compress(block, offset, is_final)` — 压缩函数：12 轮混合（简化为 4 轮）
  - `_blake2_mix(v, a, b, c, d, block, offset)` — G 混合函数：加法 + XOR + 循环移位
  - BLAKE2 状态：8 个 32 位字（h0-h7）
  - 工作向量：16 个 32 位字（v0-v15）
  - 块大小：128 字节（BLAKE2b）
  - 摘要大小：32 字节（可配置 1-64）
  - `blake2_get_hex()` — 获取哈希的十六进制表示
  - `_blake2_rotr32(val, bits)` — 循环右移：模拟 (val >> n) | (val << (32-n))
  - BLAKE2 优势：无长度扩展攻击，支持密钥哈希（HMAC 内置），可调输出长度
  - BLAKE2_BUF=0x1240000（19070976），64 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`blake2_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `blake2 hash <data>` / `blake2 hex` / `blake2 digest` / `blake2 size` / `blake2 test`

## Iteration 236 — scrypt.hl：scrypt 密钥派生

- **`bare-kernel/hl/scrypt.hl`** 新增（~260 行）
  - scrypt 密码密钥派生函数（内存困难算法）
  - 注：简化实现，N=1024（真实建议 ≥16384），受内存限制
  - 用途：密码存储，抵御 ASIC/GPU 暴力破解（比 bcrypt 更强）
  - `scrypt_derive(password, salt)` — 派生密钥：PBKDF2 + ROMix + PBKDF2
  - `_scrypt_pbkdf2(password, pwd_len, salt, salt_len, iter, dklen)` — 简化 PBKDF2
  - `_scrypt_romix(block, block_len, n)` — ROMix 内存困难函数：填充 V 数组 + 随机访问
  - `_scrypt_block_mix(block, len)` — 块混合：Salsa20/8 核心（简化）
  - scrypt 参数：N=1024（CPU/内存成本），r=8（块大小），p=1（并行度）
  - 派生密钥长度：32 字节（256 位）
  - ROMix 第一阶段：生成 N 个顺序块存入 V 数组
  - ROMix 第二阶段：根据 X 内容随机访问 V 数组并混合
  - 内存使用：N * r * 128 字节（简化版限制 N≤64 避免过大内存）
  - `scrypt_set_cost(n)` — 设置成本因子（1-4096）
  - `scrypt_get_key_hex()` — 获取派生密钥的十六进制表示
  - SCRYPT_BUF=0x1230000（19005440），512 KB 工作缓冲区（V 数组 + 中间态）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`scrypt_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `scrypt derive <pwd> <salt>` / `scrypt cost <n>` / `scrypt key` / `scrypt hex` / `scrypt test`

## Iteration 235 — bzip2.hl：bzip2 压缩算法

- **`bare-kernel/hl/bzip2.hl`** 新增（~270 行）
  - bzip2 压缩算法（Burrows-Wheeler Transform + RLE）
  - 注：简化实现，BWT 限制 256 字节块（真实 bzip2 使用 900KB 块）
  - 用途：高压缩比，优于 gzip，常用于文本压缩
  - `bzip2_compress(data, len)` — 压缩：BWT + RLE + bzip2 容器格式
  - `bzip2_decompress(data, len)` — 解压：验证魔数 + 逆 RLE + 逆 BWT
  - bzip2 文件头：魔数 "BZh"（3 字节）+ 块大小 '9'（1 字节）
  - 流头部：0x314159265359（π 的十六进制，6 字节）
  - `_bzip2_bwt(data, len)` — Burrows-Wheeler Transform：生成所有旋转 → 排序 → 提取最后一列
  - BWT 输出：变换后的字符串 + 原始位置索引
  - `_bzip2_compress_block(data, len, output, pos)` — 单块压缩：BWT + RLE
  - Run-Length Encoding：连续 ≥4 个相同字节 → 4 个字节 + 额外计数（最多 255）
  - `_bzip2_compare_rotation(data, len, rot1, rot2)` — 比较两个旋转的字典序
  - 流尾标记：0x177245385090（6 字节）
  - 流 CRC：32 位校验和（4 字节）
  - `_bzip2_crc32(data, len)` — 简化 CRC32 计算
  - BZIP2_BUF=0x1220000（18939904），512 KB 工作缓冲区（旋转数组 + 排序缓冲）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`bzip2_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `bzip2 compress <data>` / `bzip2 decompress <data>` / `bzip2 output` / `bzip2 ratio` / `bzip2 test`

## Iteration 234 — avro.hl：Apache Avro 序列化

- **`bare-kernel/hl/avro.hl`** 新增（~270 行）
  - Apache Avro 二进制编码格式（Hadoop 生态）
  - 用途：紧凑的结构化数据序列化，带模式演化支持
  - `avro_start()` — 开始新消息
  - `avro_add_boolean(value)` — 添加布尔值：0 或 1
  - `avro_add_int(value)` — 添加整数：ZigZag + varint 编码
  - `avro_add_long(value)` — 添加长整数（同 int）
  - `avro_add_string(str)` — 添加字符串：长度（varint）+ UTF-8 字节
  - `avro_add_bytes(data, len)` — 添加字节数组
  - `avro_add_int_array(array, count)` — 添加整数数组：块计数 + 元素 + 结束标记
  - ZigZag 编码：映射有符号整数到无符号（0→0, -1→1, 1→2, -2→3）
  - `_avro_zigzag_encode(n)` — 编码：n≥0 → n*2，n<0 → |n|*2-1
  - `_avro_zigzag_decode(n)` — 解码：n%2==0 → n/2，否则 → -(n+1)/2
  - `avro_decode_int(data)` — 解码整数
  - `avro_decode_string(data)` — 解码字符串
  - `avro_create_person(name, age)` — 创建简单记录：字符串 + 整数
  - `avro_decode_person(data)` — 解码记录 → "Person{name=..., age=...}"
  - AVRO_BUF=0x1210000（18874368），512 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`avro_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `avro start` / `avro addint <val>` / `avro addstr <str>` / `avro person <name> <age>` / `avro test`

## Iteration 233 — ed25519.hl：Ed25519 数字签名

- **`bare-kernel/hl/ed25519.hl`** 新增（~260 行）
  - Ed25519 数字签名算法（Edwards 曲线）
  - 注：简化实现，不包含真实椭圆曲线运算（受 H-L 语言限制）
  - 用途：现代公钥签名，速度快，安全性高（SSH/TLS 使用）
  - `ed25519_generate_keys()` — 生成密钥对：随机私钥 → 推导公钥
  - `ed25519_sign(message)` — 签名消息：生成 64 字节签名
  - `ed25519_verify(message, signature)` — 验证签名：检查签名有效性
  - 密钥大小：32 字节（256 位）
  - 签名大小：64 字节（512 位）
  - `_ed25519_hash(data, len)` — 简化哈希（真实算法使用 SHA-512）
  - 私钥生成：基于时间戳和计数器的伪随机
  - 公钥推导：简化线性变换（真实算法使用标量乘法）
  - 签名生成：私钥 + 消息哈希 → 64 字节签名（简化模式）
  - 验证：重构签名并比对（真实算法使用点加法）
  - `ed25519_get_public_key()` — 获取公钥的十六进制表示（前 16 字节 + ...）
  - `ed25519_get_signature()` — 获取签名的十六进制表示
  - ED25519_BUF=0x1200000（18874368），64 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`ed25519_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `ed25519 genkey` / `ed25519 sign <msg>` / `ed25519 verify <msg> <sig>` / `ed25519 pubkey` / `ed25519 test`

## Iteration 232 — rsa.hl：RSA 非对称加密

- **`bare-kernel/hl/rsa.hl`** 新增（~250 行）
  - RSA 非对称加密算法（简化版本）
  - 注：使用小素数演示（61, 53），不具备实际安全性
  - 用途：公钥加密，数字签名基础
  - `rsa_generate_keys()` — 生成密钥对：选择素数 p, q → 计算 n, φ(n), d
  - RSA 参数：p=61, q=53, n=3233, φ(n)=3120, e=17
  - `rsa_encrypt(message)` — 公钥加密：c = m^e mod n
  - `rsa_decrypt(ciphertext)` — 私钥解密：m = c^d mod n
  - `_rsa_mod_exp(base, exp, mod)` — 模幂运算：快速幂算法
  - `_rsa_mod_inverse(a, m)` — 模逆运算：扩展欧几里得算法
  - 公钥：(n, e)，私钥：(n, d)
  - d = e^(-1) mod φ(n) — 私钥指数计算
  - `rsa_set_public_key(n, e)` — 手动设置公钥
  - `rsa_set_private_key(n, d)` — 手动设置私钥
  - 消息限制：单字节（简化，真实 RSA 处理大块数据）
  - `rsa_get_public_key()` — 获取公钥信息字符串
  - `rsa_get_private_key()` — 获取私钥信息字符串
  - RSA_BUF=0x11F0000（18808832），64 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`rsa_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `rsa genkey` / `rsa encrypt <msg>` / `rsa decrypt <cipher>` / `rsa pubkey` / `rsa test`

## Iteration 231 — chacha20.hl：ChaCha20 流密码

- **`bare-kernel/hl/chacha20.hl`** 新增（~280 行）
  - ChaCha20 流密码（RFC 8439）现代加密算法
  - 注：简化实现，受 H-L 语言约束（无真实位运算，使用算术模拟 XOR 和循环移位）
  - 用途：对称加密，比 AES 更快，抗侧信道攻击
  - `chacha20_crypt(data, len)` — 加密/解密：生成密钥流 XOR 数据（对称操作）
  - `chacha20_set_key(key)` — 设置 256 位密钥（32 字节）
  - `chacha20_set_nonce(nonce)` — 设置 96 位 nonce（12 字节）+ 重置计数器
  - `_chacha20_block(counter)` — 生成 64 字节密钥流块：初始化状态矩阵 → 20 轮变换 → 输出
  - ChaCha20 状态矩阵（16 个 32 位字）：常量（4）+ 密钥（8）+ 计数器（1）+ nonce（3）
  - 常量："expand 32-byte k" = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
  - `_chacha20_quarter_round(state, a, b, c, d)` — 四分之一轮变换：4 次加法 + XOR + 循环移位（16/12/8/7 位）
  - 20 轮 = 10 双轮（列轮 + 对角线轮）
  - `_chacha20_rotl(value, bits)` — 循环左移：模拟 (val << n) | (val >> (32-n))
  - `_chacha20_xor(a, b)` — XOR 模拟：每字节 (a+b) % 256（简化，非标准）
  - ChaCha20 优势：纯加法/XOR/移位，无查找表（抗缓存计时攻击）
  - CHACHA20_BUF=0x11E0000（18808832），16 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`chacha20_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `chacha20 key <key>` / `chacha20 nonce <nonce>` / `chacha20 encrypt <data>` / `chacha20 decrypt <data>` / `chacha20 test`

## Iteration 230 — protobuf.hl：Protocol Buffers 序列化

- **`bare-kernel/hl/protobuf.hl`** 新增（~290 行）
  - Protocol Buffers 线格式（Google protobuf）二进制序列化
  - 用途：高效结构化数据传输，比 JSON 更紧凑
  - `protobuf_start()` — 开始新消息
  - `protobuf_add_varint(field_num, value)` — 添加 varint 字段：整数（int32/int64/bool/enum）
  - `protobuf_add_string(field_num, str)` — 添加字符串字段：长度前缀 + UTF-8 字节
  - `protobuf_add_bytes(field_num, data, len)` — 添加字节字段：二进制数据
  - `protobuf_add_fixed32(field_num, value)` — 添加定长 32 位字段（小端序）
  - `protobuf_add_fixed64(field_num, value)` — 添加定长 64 位字段（简化，仅低 32 位）
  - `_protobuf_encode_varint(buf, pos, value)` — Base-128 varint 编码：每字节 7 位数据 + 1 位延续标志
  - `_protobuf_decode_varint(buf, pos)` — varint 解码：累加直到 MSB=0
  - 线类型（wire type）：0=varint，1=64-bit，2=length-delimited，5=32-bit
  - Tag 编码：(field_number << 3) | wire_type
  - `protobuf_decode_field(data, len)` — 解析下一个字段：返回 field_num + wire_type + value/offset
  - `protobuf_format_field(field_info)` — 格式化字段信息为字符串
  - PROTOBUF_BUF=0x11D0000（18743296），512 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`protobuf_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `protobuf start` / `protobuf addint <f> <v>` / `protobuf addstr <f> <s>` / `protobuf decode <data>` / `protobuf test`

## Iteration 229 — lzma.hl：LZMA 压缩算法

- **`bare-kernel/hl/lzma.hl`** 新增（~290 行）
  - LZMA（Lempel-Ziv-Markov chain Algorithm）高压缩比算法
  - 注：简化实现，基于 LZ77 字典匹配，不包含完整范围编码器
  - 用途：7-Zip/xz 格式，压缩率优于 gzip
  - `lzma_compress(data, len)` — 压缩：LZMA 头部（13 字节）+ LZ77 编码数据
  - `lzma_decompress(data, len)` — 解压：解析头部 + 验证属性 + 字典解码
  - LZMA 头部：属性字节（lc/lp/pb）+ 字典大小（4 字节）+ 未压缩大小（8 字节）
  - `_lzma_encode(data, len, output, pos)` — LZ77 匹配编码：字面量（bit=0 + byte）或匹配（bit=1 + 距离 + 长度）
  - `_lzma_find_match(data, pos, len)` — 查找最长匹配：在 64 KB 字典中搜索 ≥2 字节重复序列
  - `_lzma_decode(data, pos, len, output, size)` — 解码：读取标志位 → 复制字面量或从字典复制匹配
  - 字典大小：64 KB（LZMA_DICT_SIZE=65536）
  - 匹配长度：2-273 字节（LZMA_MATCH_LEN_MIN/MAX）
  - 属性参数：lc=3（字面上下文位），lp=0（字面位置位），pb=2（位置位）
  - `lzma_get_ratio()` — 计算压缩率：(压缩后 / 原始) * 100
  - LZMA_BUF=0x11C0000（18677760），256 KB 工作缓冲区（字典 + 输出）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`lzma_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `lzma compress <data>` / `lzma decompress <data>` / `lzma ratio` / `lzma test`

## Iteration 228 — zlib.hl：DEFLATE 压缩算法

- **`bare-kernel/hl/zlib.hl`** 新增（~270 行）
  - DEFLATE 压缩算法（RFC 1951）+ zlib 容器格式（RFC 1950）
  - 注：简化实现，仅支持无压缩存储块（BTYPE=00），不实现 LZ77 匹配和 Huffman 编码
  - 用途：通用数据压缩，广泛用于 gzip/PNG/HTTP 压缩
  - `zlib_compress(data, len)` — 压缩数据：添加 zlib 头部（2 字节）+ 无压缩块 + Adler-32 校验和（4 字节）
  - `zlib_decompress(data, len)` — 解压数据：验证头部 + 解析块 + 校验 Adler-32
  - `_zlib_deflate(data, len, output, pos)` — DEFLATE 编码：分割成 ≤65535 字节的块，写入块头（BFINAL + BTYPE + LEN + NLEN）
  - `_zlib_inflate(data, start_pos, len, output)` — DEFLATE 解码：读取块头 + 验证 NLEN=65535-LEN + 复制字面数据
  - `_zlib_adler32(data, len)` — 计算 Adler-32 校验和：两个 16 位累加器（s1, s2）模 65521
  - zlib 头部：CMF（压缩方法=8，窗口大小=32K）+ FLG（检验位）
  - `zlib_set_level(level)` — 设置压缩级别（1-9），简化版仅影响元数据
  - `zlib_get_ratio(original_len)` — 计算压缩率：返回百分比（100=无压缩，0=完美压缩）
  - `zlib_test()` — 自测试：压缩 "Hello, ZLIB! ..." → 解压 → 验证长度
  - ZLIB_BUF=0x11B0000（18481152），256 KB 工作缓冲区（窗口 + 输出）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`zlib_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `zlib compress <data>` / `zlib decompress <data>` / `zlib level <n>` / `zlib ratio <orig> <comp>` / `zlib test`

## Iteration 227 — socks.hl：SOCKS5 代理协议

- **`bare-kernel/hl/socks.hl`** 新增（~270 行）
  - SOCKS5 代理协议客户端（RFC 1928）
  - 用途：通过代理服务器建立 TCP 连接，支持防火墙穿透和匿名访问
  - TCP 端口 1080（标准代理端口）
  - `socks_connect(dest_host, dest_port)` — 通过代理连接：连接代理 → 握手 → 连接请求
  - `_socks_handshake(sock)` — SOCKS5 握手：方法选择（无认证/用户名密码）
  - `_socks_auth_userpass(sock)` — 用户名密码认证：version=1 + ulen + username + plen + password
  - `_socks_request_connect(sock, dest_host, dest_port)` — CONNECT 请求：cmd=1 + atyp（IPv4/域名）+ addr + port
  - `socks_set_proxy(host, port)` — 配置代理服务器地址
  - `socks_set_auth(username, password)` — 设置认证凭据
  - 地址类型：ATYP_IPV4=1（4 字节 IP），ATYP_DOMAIN=3（长度 + 域名），ATYP_IPV6=4（16 字节）
  - 回复码：SUCCESS=0，FAILURE=1，NOT_ALLOWED=2，NET_UNREACHABLE=3，HOST_UNREACHABLE=4，CONN_REFUSED=5
  - `_socks_is_ip(str)` — 判断字符串是否为 IP 地址（3 个点 + 数字）
  - `socks_get_error(code)` — 获取错误描述
  - SOCKS_BUF=0x11A0000（18415616），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`socks_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `socks proxy <host> <port>` / `socks auth <user> <pass>` / `socks connect <host> <port>` / `socks close` / `socks test`

## Iteration 226 — rtp.hl：实时传输协议

- **`bare-kernel/hl/rtp.hl`** 新增（~280 行）
  - RTP（Real-time Transport Protocol）实时传输协议（RFC 3550）
  - 用途：音视频流传输，配合 RTSP 使用（RTSP 控制，RTP 传输数据）
  - UDP 传输，无固定端口（RTSP SETUP 协商）
  - `rtp_create_packet(payload_data, payload_len, marker)` — 创建 RTP 包：12 字节头部 + 载荷
  - `rtp_parse_packet(data, len)` — 解析 RTP 包：提取版本/载荷类型/序列号/时间戳/SSRC
  - RTP 头部（12 字节）：V(2) + P(1) + X(1) + CC(4) + M(1) + PT(7) + Sequence(16) + Timestamp(32) + SSRC(32)
  - V（版本）：固定为 2
  - M（Marker）：标记位，用于标识关键帧或片段结束
  - PT（Payload Type）：载荷类型，0=PCMU，8=PCMA，31=H.261，32=MPV
  - SSRC（同步源标识符）：随机生成 32 位标识符，区分不同音视频流
  - 序列号：每个包递增，用于检测丢包和重排序
  - 时间戳：基于采样率递增（如 8kHz 音频每 20ms 增加 160）
  - `rtp_set_payload_type(pt)` — 设置载荷类型（0-127）
  - `rtp_get_payload_name(pt)` — 获取载荷类型名称（PCMU/G722/H261/MPV 等）
  - `_rtp_generate_ssrc()` — 生成随机 SSRC：基于 uptime 和 ticks 哈希
  - RTP_BUF=0x1190000（18350080），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`rtp_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `rtp create <len> <mark>` / `rtp parse <data>` / `rtp setpt <pt>` / `rtp info` / `rtp test`

## Iteration 225 — stun.hl：STUN NAT 穿透协议

- **`bare-kernel/hl/stun.hl`** 新增（~260 行）
  - STUN（Session Traversal Utilities for NAT）NAT 会话穿透工具（RFC 5389）
  - 用途：发现公网 IP 地址和 NAT 类型，用于 VoIP/WebRTC 连接建立
  - UDP 端口 3478，二进制协议
  - `stun_create_binding_request()` — 创建绑定请求：20 字节固定头部（消息类型 + 长度 + Magic Cookie + 事务 ID）
  - `stun_parse_response(data)` — 解析绑定响应：提取 MAPPED-ADDRESS 或 XOR-MAPPED-ADDRESS
  - STUN 消息类型：BINDING_REQUEST=0x0001，BINDING_RESPONSE=0x0101
  - STUN 属性：MAPPED_ADDRESS=0x0001，XOR_MAPPED_ADDRESS=0x0020
  - Magic Cookie：0x2112A442（固定值，用于区分 STUN 和其他协议）
  - `_stun_generate_transaction_id()` — 生成 12 字节随机事务 ID
  - `stun_get_mapped_address()` — 获取映射地址：IP:Port 格式字符串
  - XOR 映射：端口 XOR Magic_Cookie_High16，IP XOR Magic_Cookie
  - `stun_selftest()` — 测试请求构建：验证消息类型 + Magic Cookie
  - STUN_BUF=0x1180000（18284544），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`stun_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `stun request` / `stun parse <data>` / `stun addr` / `stun test`

## Iteration 224 — rtsp.hl：RTSP 流媒体协议

- **`bare-kernel/hl/rtsp.hl`** 新增（~280 行）
  - RTSP（Real-Time Streaming Protocol）实时流协议（RFC 2326）
  - 用途：控制流媒体服务器（播放/暂停/停止），类 HTTP 文本协议
  - TCP 端口 554，协议版本 RTSP/1.0
  - `rtsp_create_options(url)` — 创建 OPTIONS 请求：查询服务器支持的方法
  - `rtsp_create_describe(url)` — 创建 DESCRIBE 请求：获取 SDP 媒体描述
  - `rtsp_create_setup(url, client_port)` — 创建 SETUP 请求：建立传输通道（RTP/AVP unicast）
  - `rtsp_create_play(url)` — 创建 PLAY 请求：开始流媒体播放（Range: npt=0.000-）
  - `rtsp_create_pause(url)` — 创建 PAUSE 请求：暂停播放
  - `rtsp_create_teardown(url)` — 创建 TEARDOWN 请求：关闭会话
  - `rtsp_parse_response(data)` — 解析响应：提取状态码 + Session ID
  - RTSP 头部：CSeq（命令序列号），Session（会话标识符），Transport（传输参数）
  - CSeq 自增：每个请求递增，保证顺序
  - `rtsp_selftest()` — 测试 OPTIONS + DESCRIBE + SETUP 请求构建
  - RTSP_BUF=0x1170000（18219008），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`rtsp_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `rtsp options <url>` / `rtsp describe <url>` / `rtsp setup <url> <port>` / `rtsp play <url>` / `rtsp pause <url>` / `rtsp teardown <url>` / `rtsp test`

## Iteration 223 — bcrypt.hl：Bcrypt 密码哈希

- **`bare-kernel/hl/bcrypt.hl`** 新增（~270 行）
  - Bcrypt 自适应密码哈希函数（基于 Blowfish 密码）
  - 注：简化教学实现，受 H-L 语言约束（无真实位运算，使用算术模拟）
  - 用途：密码存储，慢速设计（cost 因子）抵御暴力破解
  - `bcrypt_hash(password)` — 生成哈希：随机盐 + cost 轮次 → $2b$cost$salt_hash 格式
  - `bcrypt_verify(password, hash)` — 验证密码：重新哈希 + 前缀匹配
  - `bcrypt_set_cost(cost)` — 设置成本因子（4-31），cost=10 → 2^10=1024 轮迭代
  - `_bcrypt_generate_salt()` — 生成 16 字节随机盐
  - `_bcrypt_expand_key(password)` — 密钥扩展：密码 + 盐 → 18 个状态字
  - `_bcrypt_rounds(state, rounds)` — 多轮变换：模拟 Blowfish Feistel 网络
  - Bcrypt 格式：$2b$cost$salt（22 字符 Base64）+ hash（31 字符 Base64）
  - Base64 编码：自定义字符表（A-Z/a-z/0-9/+/）
  - `bcrypt_selftest()` — 测试密码 "test_password" → 哈希 → 验证正确/错误密码
  - BCRYPT_BUF=0x1160000（18153472），64 KB 工作缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`bcrypt_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `bcrypt cost <n>` / `bcrypt hash <pwd>` / `bcrypt verify <pwd> <hash>` / `bcrypt test`

## Iteration 222 — sip.hl：SIP VoIP 信令协议

- **`bare-kernel/hl/sip.hl`** 新增（~290 行）
  - SIP（Session Initiation Protocol）会话初始协议（RFC 3261）
  - 用途：VoIP 呼叫建立/修改/终止信令，文本协议
  - UDP/TCP 端口 5060（明文）/5061（TLS）
  - `sip_create_invite(from, to, host)` — 创建 INVITE 请求：呼叫邀请 + SDP 媒体描述
  - `sip_create_ack(to, host)` — 创建 ACK 请求：确认 INVITE 响应
  - `sip_create_bye(to, host)` — 创建 BYE 请求：挂断呼叫
  - `sip_create_register(user, registrar)` — 创建 REGISTER 请求：注册到 SIP 服务器（3600 秒过期）
  - `sip_parse_response(data)` — 解析 SIP 响应：提取状态码（200/180/486 等）
  - SIP 头部：Via, From, To, Call-ID, CSeq, Contact, Max-Forwards, User-Agent
  - `sip_set_local(ip, port)` — 设置本地 SIP 端点（IP + 端口）
  - SDP 会话描述：v=0, o=, s=, c=, t=, m=audio（RTP/AVP PCMU/8000）
  - Call-ID 自增 + CSeq 自增，保证消息唯一性
  - `sip_selftest()` — 测试 INVITE + REGISTER 消息构建
  - SIP_BUF=0x1150000（18087936），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`sip_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `sip local <ip> <port>` / `sip invite <from> <to> <host>` / `sip ack <to> <host>` / `sip bye <to> <host>` / `sip register <user> <reg>` / `sip parse <data>` / `sip test`

## Iteration 221 — dhcp_server.hl：DHCP 服务器

- **`bare-kernel/hl/dhcp_server.hl`** 新增（~310 行）
  - DHCP Server（Dynamic Host Configuration Protocol Server）动态主机配置服务器
  - 用途：为客户端分配 IP 地址、子网掩码、网关、DNS
  - UDP 端口 67（服务器）/68（客户端）
  - `dhcp_server_process(request)` — 处理 DISCOVER/REQUEST 请求 → 返回 OFFER/ACK
  - `_dhcp_srv_allocate_ip(mac_high, mac_low)` — 分配 IP：从地址池分配 + 记录租约（MAC → IP 映射）
  - 地址池管理：pool_start → pool_end，最多 32 个租约
  - 租约数组：[mac_high, mac_low, ip] × 32，支持同 MAC 重复获取同 IP
  - `dhcp_server_set_pool(start, end)` — 设置 IP 地址池范围
  - `dhcp_server_set_options(subnet, router, dns)` — 设置网络配置选项
  - DHCP 选项：SUBNET=1, ROUTER=3, DNS=6, LEASE_TIME=51, MSG_TYPE=53, SERVER_ID=54
  - 消息类型：DISCOVER=1, OFFER=2, REQUEST=3, ACK=5, NAK=6
  - 报文结构：OP + HTYPE + HLEN + HOPS + XID(4B) + SECS + FLAGS + CIADDR + YIADDR + SIADDR + GIADDR + CHADDR(16B) + SNAME + FILE + OPTIONS
  - `dhcp_server_list_leases()` — 列出当前租约表（IP 分配情况）
  - `dhcp_selftest()` — 测试地址分配：同 MAC 获取同 IP
  - DHCP_SRV_BUF=0x1140000（18022400），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`dhcp_server_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `dhcpsrv start` / `dhcpsrv pool <start> <end>` / `dhcpsrv options <subnet> <router> <dns>` / `dhcpsrv leases` / `dhcpsrv test`

## Iteration 220 — sha256.hl：SHA-256 哈希算法

- **`bare-kernel/hl/sha256.hl`** 新增（~290 行）
  - SHA-256（Secure Hash Algorithm 256-bit）安全哈希算法（FIPS 180-4）
  - 注：简化教学实现，受 H-L 语言约束（无真实位运算，使用算术模拟）
  - 256 位（32 字节）哈希输出，SHA-2 家族，比 SHA-1 更安全
  - `sha256_hash(data)` — 哈希计算：初始化 8 个状态变量（h0-h7）+ 64 轮常量（k0-k63）
  - `sha256_get_hex()` — 256 位 → 64 字符十六进制字符串
  - `_sha256_rotr(val, shift)` — 循环右移：模拟位运算（val >> shift | val << (32-shift)）
  - `_sha256_ch(x, y, z)` — CH 函数：if x then y else z（逐位模拟）
  - `_sha256_maj(x, y, z)` — MAJ 函数：多数函数（x, y, z 中至少 2 个为 1）
  - `_sha256_sigma0/sigma1()` — Σ 函数：多次循环移位 XOR
  - 初始状态：h0=1779033703, h1=3144134277, ..., h7=1541459225
  - 64 个轮常量 k：从前 64 个素数立方根的小数部分导出
  - `sha256(data)` — 便捷接口：hash + get_hex
  - `sha256_selftest()` — 测试空字符串 + "abc" + 句子 → 64 字符哈希
  - SHA256_BUF=0x1130000（17956864），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`sha256_init()`
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：
  - `sha256 <text>` / `sha256 test`

## Iteration 219 — radius.hl：RADIUS 认证协议

- **`bare-kernel/hl/radius.hl`** 新增（~310 行）
  - RADIUS（Remote Authentication Dial-In User Service）远程认证拨号用户服务（RFC 2865）
  - 用途：集中式 AAA（认证/授权/计费）协议，企业网络访问控制
  - UDP 端口 1812（认证）/1813（计费）
  - `radius_create_access_request(username, password)` — 创建访问请求报文：Code=1 + Identifier + Length(2B) + Authenticator(16B) + 属性
  - `radius_send_request(server, port)` — 发送 UDP 请求：创建 socket + udp_send
  - `radius_parse_response(data)` — 解析响应：Code=2（Accept）/3（Reject）
  - `_radius_encrypt_password(pwd, auth)` — 密码加密：XOR with MD5(secret + authenticator)，16 字节分块
  - `_radius_add_attribute(type, data)` — 添加属性：TLV 格式（Type + Length + Value）
  - RADIUS 属性：USER_NAME=1，USER_PASSWORD=2，NAS_IP=4，SERVICE_TYPE=6
  - `radius_set_secret(secret)` — 设置共享密钥（用于密码加密和消息完整性）
  - 报文结构：Code(1B) + Identifier(1B) + Length(2B) + Authenticator(16B) + Attributes(变长)
  - `radius_selftest()` — 测试报文构建：用户名 "testuser" + 密码 "testpass" → Access-Request
  - RADIUS_BUF=0x1120000（17891328），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`radius_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `radius secret <secret>` / `radius request <user> <pwd>` / `radius send <server>` / `radius parse <data>` / `radius test`

## Iteration 218 — huffman.hl：霍夫曼编码压缩

- **`bare-kernel/hl/huffman.hl`** 新增（~280 行）
  - Huffman Coding（霍夫曼编码）可变长度前缀编码压缩算法
  - 用途：无损压缩，高频符号使用短码，低频符号使用长码
  - `huffman_encode(data)` — 编码：构建频率表 → 排序 → 生成码表 → 位流编码
  - `huffman_decode(data)` — 解码：读取码表 → 位流解码 → 符号输出
  - `_huffman_build_freq_table(data)` — 频率统计：256 字节符号 → 出现次数数组
  - `_huffman_build_simple_codes()` — 简化码表生成：按频率排序 → 分配码长（1-16 位）
  - 码表格式：符号数量 + [符号, 码长, 码值] × N
  - 位缓冲：累积 8 位后写入字节流，最后不足 8 位填充 0
  - `huffman_ratio(orig_len, comp_len)` — 压缩率计算：(compressed / original) × 100%
  - `huffman_get_result()` — 获取编码/解码结果二进制字符串
  - `huffman_selftest()` — 测试 "AAAABBBCCD" → 压缩 → 解压 → 验证
  - HUFFMAN_BUF=0x1110000（17825792），64 KB 输出缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`huffman_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `huffman encode <data>` / `huffman decode <data>` / `huffman ratio <orig> <comp>` / `huffman test`

## Iteration 217 — aes.hl：AES 加密算法

- **`bare-kernel/hl/aes.hl`** 新增（~290 行）
  - AES（Advanced Encryption Standard）高级加密标准（FIPS 197）
  - 注：简化教学实现，受 H-L 语言约束（无真实位运算，使用算术模拟）
  - AES-128：128 位密钥 + 128 位数据块 + 10 轮加密
  - `aes_set_key(key)` — 设置 16 字节密钥（不足补零）
  - `aes_encrypt(plaintext)` — 加密：分 16 字节块 → 10 轮变换 → 密文输出
  - `aes_decrypt(ciphertext)` — 解密：逆变换（简化版）
  - `_aes_sub_bytes()` — S 盒替换：每字节通过 256 字节查找表映射
  - `_aes_shift_rows()` — 行移位：4×4 状态矩阵行循环移位（0/1/2/3）
  - `_aes_add_round_key()` — 轮密钥加：状态 XOR 轮密钥（算术模拟：(s + k) % 256）
  - S-box：256 字节查找表（Rijndael 标准 S 盒）
  - `aes_get_hex()` — 密文十六进制输出（调试友好）
  - `aes_selftest()` — 测试 "Hello AES World!" + 密钥 "0123456789abcdef" → 加密 → 解密
  - AES_BUF=0x1100000（17825792），64 KB 数据缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`aes_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `aes key <key>` / `aes encrypt <data>` / `aes decrypt <data>` / `aes hex` / `aes test`

## Iteration 216 — ldap.hl：LDAP 目录访问协议

- **`bare-kernel/hl/ldap.hl`** 新增（~310 行）
  - LDAP（Lightweight Directory Access Protocol）轻量级目录访问协议（RFC 4511）
  - 用途：访问和维护分布式目录信息服务（用户/组/资源查询）
  - TCP 端口 389，使用 ASN.1 BER 编码
  - `ldap_connect(host)` — 连接 LDAP 服务器：创建 TCP socket + 连接 port 389
  - `ldap_bind(dn, password)` — 绑定认证：发送 BindRequest（消息 ID + 版本 3 + DN + 密码）
  - `ldap_search(base_dn, filter, scope)` — 搜索请求：发送 SearchRequest（base DN + 过滤器 + 作用域 0-2）
  - `ldap_unbind()` — 解绑并断开：发送 UnbindRequest + 关闭 socket
  - `_ldap_encode_int(value)` — 整数 ASN.1 编码：tag 0x02 + 长度 + 大端序字节
  - `_ldap_encode_string(str)` — 字符串 ASN.1 编码：tag 0x04 + 长度 + UTF-8 字节
  - `_ldap_encode_length(len)` — 长度编码：短格式（<128）或长格式（≥128，多字节）
  - LDAP 操作码：BIND=0，UNBIND=2，SEARCH=3，MODIFY=6，ADD=8，DELETE=10
  - `ldap_selftest()` — 测试 ASN.1 编码：整数/字符串/长度编码验证
  - LDAP_BUF=0x10F0000（17825792），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`ldap_init()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `ldap connect <host>` / `ldap bind <dn> <pwd>` / `ldap search <dn> <filter>` / `ldap unbind` / `ldap disconnect` / `ldap test`

## Iteration 215 — rss.hl：RSS 订阅源解析器

- **`bare-kernel/hl/rss.hl`** 新增（~320 行）
  - RSS（Really Simple Syndication）简易信息聚合格式（RSS 2.0 / Atom）
  - 用途：解析新闻源/博客订阅 XML 文档，提取频道和条目信息
  - `rss_parse(xml)` — 解析 RSS/Atom XML 文档 → 提取频道和条目数据
  - `_rss_find_tag(xml, tag, start_pos)` — 查找 XML 标签：定位 `<tag>...</tag>` → 返回内容 + 下一位置
  - `_rss_decode_entities(text)` — HTML 实体解码：&lt; → <，&gt; → >，&amp; → &，&quot; → "，&apos; → '
  - `_rss_strip_cdata(text)` — CDATA 节点提取：<![CDATA[...]]> → 纯文本内容
  - `rss_get_channel_title/link/desc()` — 获取频道元数据（标题/链接/描述）
  - `rss_get_item_title/link/desc/date(index)` — 获取条目信息（标题/链接/描述/发布日期）
  - `rss_get_item_count()` — 返回已解析条目数量
  - 最多存储 32 条目：并行数组（titles/links/descs/dates）
  - `rss_selftest()` — 测试 XML 解析：2 条目 + 频道标题验证
  - RSS_BUF=0x10E0000（17760256），64 KB XML 缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`rss_init()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `rss parse <xml>` / `rss channel` / `rss items` / `rss item <n>` / `rss count` / `rss test`

## Iteration 214 — rle.hl：行程长度编码

- **`bare-kernel/hl/rle.hl`** 新增（~200 行）
  - RLE（Run-Length Encoding）行程长度编码压缩算法
  - 用途：无损压缩重复数据（图像/简单文本），对连续重复字节高效
  - `rle_encode(data)` — 编码数据：连续 ≥3 字节 → (0x00, count, byte)，否则直接存储
  - `rle_decode(data)` — 解码数据：遇到 0x00 + count + byte → 展开重复，否则直接输出
  - 特殊处理：单独 0x00 字节编码为 (0x00, 1, 0x00) 避免歧义
  - 最大连续长度 255（单字节 count）
  - `rle_encode_to_hex(data)` — 编码 + 十六进制输出：字节流 → 十六进制字符串（调试友好）
  - `rle_ratio(orig_len, comp_len)` — 压缩率计算：(compressed / original) × 100%
  - `rle_get_result()` — 获取编码/解码结果二进制字符串
  - `rle_selftest()` — 测试压缩/解压：重复数据 + 普通数据 + 往返一致性验证
  - RLE_BUF=0x10D0000（17694720），64 KB 输出缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`rle_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `rle encode <data>` / `rle decode <data>` / `rle ratio <orig> <comp>` / `rle hex <data>` / `rle test`

## Iteration 213 — uuid.hl：UUID 生成器

- **`bare-kernel/hl/uuid.hl`** 新增（~150 行）
  - UUID（Universally Unique Identifier）通用唯一标识符（RFC 4122）
  - 支持 UUID v4（随机）生成：128 位唯一标识符
  - 标准格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx（36 字符含连字符）
  - `uuid_v4()` — 生成随机 UUID：16 字节随机数 + 版本位设置（byte[6] = 0x40-0x4F，byte[8] = 0x80-0xBF）
  - `_uuid_random_byte()` — 随机字节生成（random_get() % 256）
  - `uuid_nil()` — 返回 nil UUID（全零）："00000000-0000-0000-0000-000000000000"
  - `uuid_parse(uuid_str)` — 解析 UUID 字符串 → 16 字节二进制（跳过连字符，十六进制 → 字节）
  - `uuid_validate(uuid_str)` — 验证 UUID 格式：长度 36 + 连字符位置（8/13/18/23）+ 十六进制字符
  - `uuid_get_version(uuid_str)` — 提取版本号（第 15 字符 → 十六进制 → 版本）
  - `uuid_selftest()` — 生成 2 个 UUID → 验证格式 + 提取版本号
  - UUID_BUF=0x10C0000（17563648），4 KB 缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`uuid_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `uuid` / `uuid v4` / `uuid nil` / `uuid validate <uuid>` / `uuid test`

## Iteration 212 — pbkdf2.hl：PBKDF2 密钥派生

- **`bare-kernel/hl/pbkdf2.hl`** 新增（~180 行）
  - PBKDF2（Password-Based Key Derivation Function 2）基于密码的密钥派生函数（RFC 2898）
  - 用途：从密码派生加密密钥，增加暴力破解成本（迭代计算）
  - `pbkdf2_sha1(pwd, salt, iter, keylen)` — 使用 HMAC-SHA1 派生密钥
  - `pbkdf2_md5(pwd, salt, iter, keylen)` — 使用 HMAC-MD5 派生密钥
  - 算法：F(P, S, c, i) = U1 XOR U2 XOR ... XOR Uc，其中 U1 = HMAC(P, S || INT(i))，Un = HMAC(P, Un-1)
  - `_pbkdf2_int_to_bytes(n)` — 32 位整数 → 4 字节大端序
  - `_pbkdf2_xor_strings(s1, s2)` — 字符串逐字节 XOR（模拟位运算）
  - `_pbkdf2_hex_to_bytes(hex)` — 十六进制字符串 → 二进制字节序列
  - 分块处理：keylen / hash_output_len 向上取整 → 多块拼接
  - `pbkdf2_selftest()` — 测试 "password"/"salt"/2 迭代/16 字节 → 输出派生密钥
  - PBKDF2_BUF=0x10B0000（17498112），64 KB 缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`pbkdf2_init()`
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：
  - `pbkdf2 <pwd> <salt> <iter> <len>` / `pbkdf2 test`

## Iteration 211 — hmac.hl：HMAC 消息认证码

- **`bare-kernel/hl/hmac.hl`** 新增（~130 行）
  - HMAC（Hash-based Message Authentication Code）基于哈希的消息认证码（RFC 2104）
  - 用途：使用密钥 + 哈希函数验证消息完整性和真实性，防止长度扩展攻击
  - `hmac_md5(key, message)` — HMAC-MD5：128 位输出
  - `hmac_sha1(key, message)` — HMAC-SHA1：160 位输出
  - 算法：HMAC(K, m) = H((K' XOR opad) || H((K' XOR ipad) || m))
  - `_hmac_xor_byte(a, b)` — 字节级 XOR（逐位模拟，无位运算）
  - `_hmac_pad_key(key, block_size)` — 密钥填充：key 长度 < block_size → 右填充 0x00，= block_size → 直接使用
  - ipad = 0x36（重复 64 次），opad = 0x5C（重复 64 次）
  - 内部哈希：inner = H(K' XOR ipad || message)，外部哈希：outer = H(K' XOR opad || inner)
  - `hmac_selftest()` — 测试 key="secret"、message="hello" → HMAC-MD5 + HMAC-SHA1 输出
  - HMAC_BUF=0x10A0000（17432576），64 KB 缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`hmac_init()`
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `hmac-md5 <key> <msg>` / `hmac-sha1 <key> <msg>` / `hmac test`

## Iteration 210 — sha1.hl：SHA-1 哈希算法

- **`bare-kernel/hl/sha1.hl`** 新增（~160 行）
  - SHA-1（Secure Hash Algorithm 1）产生 160 位哈希值（RFC 3174）
  - 注：SHA-1 已被弃用于加密用途，仅用于校验和
  - `sha1_init()` — 初始化 5 个状态变量（h0-h4）= 1732584193/4023233417/2562383102/271733878/3285377520
  - `sha1_hash(data)` — 简化实现：逐轮累加状态变量（模拟消息块处理）
  - `_sha1_rotl(val, shift)` — 循环左移（模拟位运算）：高位检测 → 乘 2 → 低位加 1
  - `_sha1_parity(x, y, z)` — XOR 奇偶函数（逐位异或模拟）
  - `sha1_get_hex()` — 160 位状态 → 40 字符十六进制字符串（5×32 位 → 5×8 字符）
  - `sha1(data)` — 便捷接口：hash + get_hex
  - `sha1_selftest()` — 测试空字符串 + "abc" → 输出哈希（简化实现，哈希仅示意）
  - SHA1_BUF=0x1090000（17367040），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`sha1_init()`
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：
  - `sha1 <text>` / `sha1 test`

## Iteration 209 — md5.hl：MD5 哈希算法

- **`bare-kernel/hl/md5.hl`** 新增（~150 行）
  - MD5（Message-Digest Algorithm 5）产生 128 位哈希值（RFC 1321）
  - 注：MD5 已被加密破解，仅用于校验和
  - `md5_init()` — 初始化 4 个状态变量（h0-h3）= 1732584193/4023233417/2562383102/271733878
  - `md5_hash(data)` — 简化实现：逐轮累加状态变量（模拟 4 轮处理）
  - `_md5_rotl(val, shift)` — 循环左移：高位→2147483648 检测 → *2 → +1
  - `_md5_h(x, y, z)` — H 函数（XOR 异或）：逐位模拟 x XOR y XOR z
  - `md5_get_hex()` — 128 位状态 → 32 字符十六进制字符串（4×32 位 → 4×8 字符）
  - `md5(data)` — 便捷接口：hash + get_hex
  - `md5_selftest()` — 测试空字符串 + "abc" → 输出哈希（简化实现，哈希仅示意）
  - MD5_BUF=0x1080000（17301504），64 KB 消息缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`md5_init()`
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：
  - `md5 <text>` / `md5 test`

## Iteration 208 — crc.hl：CRC 校验和

- **`bare-kernel/hl/crc.hl`** 新增（~180 行）
  - CRC（循环冗余校验）— 数据传输/存储错误检测码
  - 支持 CRC8（多项式 0x07，初始 0x00）、CRC16（多项式 0x8005，初始 0x0000）、CRC32（多项式 0x04C11DB7，初始 0xFFFFFFFF）
  - `crc8(data)` — 8 位 CRC：逐字节处理，逐位异或 + 多项式除法（模拟位运算）
  - `crc16(data)` — 16 位 CRC：高字节 + 低字节混合，检测 ≥32768 → 左移 + 多项式异或
  - `crc32(data)` / `crc32_simple(data)` — 32 位 CRC：查表法 + 简化累加法
  - `crc_table32[]` — CRC32 查找表（256 项，初始化时生成）
  - `crc_to_hex(val, digits)` — 整数 → 十六进制字符串（指定位数）
  - `crc_selftest()` — 测试 "123456789" → CRC8/CRC16/CRC32 输出
  - CRC_BUF=0x1070000（17235968），64 KB 数据缓冲区
  - 注：无位运算，纯整数模拟（/, %, +, -）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`crc_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `crc8 <text>` / `crc16 <text>` / `crc32 <text>` / `crc test`

## Iteration 207 — url.hl：URL 编码/解码（百分号编码）

- **`bare-kernel/hl/url.hl`** 新增（~200 行）
  - URL 编码（百分号编码）— 特殊字符安全传输（RFC 3986）
  - 非保留字符（A-Z/a-z/0-9/-/\_/./~）→ 直接传输；其他字符 → %XX（百分号 + 2 位十六进制）
  - `_url_is_unreserved(c)` — 判断字符是否为非保留字符（无需编码）
  - `url_encode(data)` — 逐字符扫描，非保留字符直通，其他转义为 %XX（hi/lo 十六进制）
  - `url_decode(data)` — 解析 %XX → 字节值，支持 + → 空格（传统 form 编码）
  - `_url_hex_digit(n)` / `_url_from_hex(c)` — 0-15 ↔ 0-9/A-F 转换
  - `url_parse_query(query)` — 解析查询字符串（key=value&key=value）→ 解码 + 格式化输出
  - `url_selftest()` — "hello world" → "hello%20world" → 解码 → 验证往返
  - URL_BUF=0x1060000（17170432），64 KB 编码/解码缓冲区
  - 空格编码为 %20（不是 +），符合 RFC 3986 标准
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`url_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `url enc <text>` / `url dec <text>` / `url query <str>` / `url test`

## Iteration 206 — hex.hl：十六进制编码/解码工具

- **`bare-kernel/hl/hex.hl`** 新增（~210 行）
  - 十六进制编码 — 二进制数据 → 可读十六进制字符串（每字节 → 2 字符）
  - `hex_encode(data)` — 逐字节转换：hi = byte/16, lo = byte%16 → 0-9/A-F
  - `hex_decode(data)` — 逐对字符解析：忽略分隔符（空格/冒号/短横线）→ 字节值
  - `_hex_to_char(n)` — 0-15 → '0'-'9'/'A'-'F'
  - `_hex_from_char(c)` — '0'-'9'/'A'-'F'/'a'-'f' → 0-15（大小写不敏感）
  - `hex_dump(data, offset, len)` — 格式化十六进制转储（地址 + 十六进制 + ASCII）
  - 转储格式：每行 16 字节，8 位地址 + 间隔 + 16×2 字符 + ASCII 视图（不可打印字符显示为 .）
  - `hex_selftest()` — "abc" → "616263" → 解码 → 验证往返
  - HEX_BUF=0x1050000（17104896），64 KB 编码/解码缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`hex_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `hex enc <text>` / `hex dec <text>` / `hex dump <text>` / `hex test`

## Iteration 205 — base32.hl：Base32 编码/解码

- **`bare-kernel/hl/base32.hl`** 新增（~230 行）
  - Base32 二进制-文本编码 — 使用 32 个可打印字符（RFC 4648）
  - 字符集：A-Z（26 字符）+ 2-7（6 字符）= 32，大小写不敏感
  - 编码效率：5 位/字符，8 字节 → 13 字符（含填充）
  - `base32_encode(data)` — 5 字节块 → 8 Base32 字符，不足部分填充 '='
  - 位操作模拟：c0 = b0/8, c1 = (b0%8)*4 + b1/64, c2 = (b1/2)%32, ...（纯整数运算）
  - `base32_decode(data)` — 8 字符 → 5 字节，大小写不敏感（a-z → A-Z）
  - `_base32_encode_char(n)` — 0-25 → A-Z, 26-31 → 2-7
  - `_base32_decode_char(c)` — A-Z/a-z → 0-25, 2-7 → 26-31
  - `base32_selftest()` — "hello" → "NBSWY3DP" → 解码 → 验证往返
  - BASE32_BUF=0x1040000（17039360），64 KB 编码/解码缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`base32_init()`
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `base32 enc <text>` / `base32 dec <text>` / `base32 test`

## Iteration 204 — wav.hl：WAV 音频格式解析器

- **`bare-kernel/hl/wav.hl`** 新增（~280 行）
  - WAV（Waveform Audio File Format）基于 RIFF 容器的音频格式（Microsoft/IBM）
  - 结构：RIFF 头（12B）+ fmt 块（24B+）+ data 块（音频数据）
  - `wav_parse()` — 解析 RIFF/WAVE 头，遍历块（fourcc + size）
  - `_wav_read_fourcc(offset)` — 读取 4 字符代码（"RIFF"/"WAVE"/"fmt "/"data"）
  - fmt 块解析：音频格式（1=PCM）、通道数、采样率、字节率、对齐、位深度
  - `wav_get_sample_rate/channels/bits_per_sample()` — 提取音频元数据
  - `wav_get_duration_ms()` — 计算时长（毫秒）= (样本总数 × 1000) / 采样率
  - `wav_info()` — 格式化输出：采样率（Hz）+ 通道 + 位深 + 数据大小 + 时长
  - `wav_play()` — 播放音频（预留接口，依赖 AC97/AudioServer）
  - `wav_selftest()` — 构造 44100 Hz 立体声 16 位 PCM 头 → 解析验证
  - WAV_BUF=0x1030000（16973824），256 KB 音频缓冲区
  - 支持 PCM 格式（audio_format=1），不支持压缩格式
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`wav_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `wav load <path>` / `wav info` / `wav play` / `wav test`

## Iteration 203 — gif.hl：GIF 图像解码器

- **`bare-kernel/hl/gif.hl`** 新增（~230 行）
  - GIF（Graphics Interchange Format）位图图像格式，支持 256 色 + LZW 压缩
  - 结构：头（6B "GIF87a"/"GIF89a"）+ 逻辑屏幕描述符 + 全局颜色表 + 图像数据
  - `gif_parse()` — 解析签名（GIF）+ 版本 + 宽高
  - 逻辑屏幕描述符：宽高（2B×2，小端序）+ packed 字段（全局颜色表标志 + 颜色位数）
  - `gif_palette[]` — 存储全局颜色表（RGB 三元组，parallel array）
  - packed 字段解析：has_gct（bit 7）+ color_bits（bits 0-2）→ 颜色数 = 2^(color_bits+1)
  - `gif_get_palette_color(idx)` — 索引 → RGB888 颜色值（r*65536 + g*256 + b）
  - `gif_list_palette()` — 输出调色板前 16 色（RGB 值）
  - `gif_info()` — 格式化输出：宽高 + 颜色数 + 颜色位数
  - `gif_selftest()` — 构造 32×32 GIF89a 头（2 色全局调色板）→ 解析验证
  - GIF_BUF=0x1020000（16908288），256 KB 图像缓冲区
  - 注：未实现 LZW 解压缩和图像数据块解析（仅头部 + 调色板）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`gif_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `gif load <path>` / `gif info` / `gif palette` / `gif test`

## Iteration 202 — bmp.hl：BMP 位图图像解码器

- **`bare-kernel/hl/bmp.hl`** 新增（~250 行）
  - BMP（Bitmap）简单光栅图形格式（Windows Bitmap）
  - 结构：文件头（14B）+ DIB 头（40B+）+ 像素数据
  - `bmp_parse()` — 解析 "BM" 签名 + 文件大小 + 数据偏移
  - 文件头：签名（2B "BM"）+ 文件大小（4B）+ 保留（4B）+ 数据偏移（4B）
  - DIB 头（BITMAPINFOHEADER）：头大小（40）+ 宽高（4B×2，有符号）+ 平面数（2B）+ 位深（2B）+ 压缩（4B）
  - `_bmp_read_u16/u32/i32(offset)` — 小端序整数读取
  - `bmp_get_pixel(x, y)` — 读取 24 位 RGB 像素（BGR 顺序），处理行对齐（4 字节）和倒序（bottom-up）
  - `bmp_display(x, y)` — 将图像绘制到 VESA framebuffer（逐像素写入）
  - `bmp_info()` — 格式化输出：宽高 + 位深 + 数据偏移
  - `bmp_selftest()` — 构造 16×16 24 位 BMP 头 → 解析验证
  - BMP_BUF=0x1010000（16842752），256 KB 图像缓冲区
  - 仅支持 BI_RGB（未压缩）格式
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`bmp_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `bmp load <path>` / `bmp info` / `bmp show <x> <y>` / `bmp test`

## Iteration 201 — jwt.hl：JSON Web Token 解析/验证

- **`bare-kernel/hl/jwt.hl`** 新增（~270 行）
  - JWT（JSON Web Token）认证令牌格式：header.payload.signature（Base64url 编码）
  - `jwt_parse(token)` — 按 `.` 分割三部分，Base64url 解码 header + payload
  - `_jwt_base64url_decode(data)` — Base64url 变体（`-` 代替 `+`，`_` 代替 `/`，无填充）
  - `_jwt_extract_claim(payload, name)` — JSON 字段提取（简单字符串匹配）
  - `jwt_get_sub/iss/aud()` — 标准声明提取（subject/issuer/audience）
  - `jwt_get_exp/iat()` — 时间戳声明（expiry/issued at）→ parse_int
  - `jwt_is_expired()` — 验证 exp 声明是否过期（vs rtc_read_timestamp）
  - `jwt_display()` — 格式化输出 header + payload + 声明列表 + 过期状态
  - `jwt_selftest()` — 解析标准测试 JWT（sub="1234567890", name="John Doe", iat=1516239022）
  - JWT_BUF=0x1000000（16777216），64 KB 解码缓冲区
  - 注：未实现签名验证（需要 HMAC-SHA256）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`jwt_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `jwt parse <token>` / `jwt header` / `jwt payload` / `jwt sub` / `jwt iss` / `jwt exp` / `jwt test`

## Iteration 200 — pem.hl：PEM 格式解析器

- **`bare-kernel/hl/pem.hl`** 新增（~290 行）
  - PEM（Privacy Enhanced Mail）格式：Base64 编码 + BEGIN/END 标记（X.509 证书、私钥）
  - 格式结构：`-----BEGIN <LABEL>-----` / Base64 数据（多行）/ `-----END <LABEL>-----`
  - `pem_parse(data)` — 提取 label + Base64 内容，过滤空白字符（空格/制表符/换行）
  - `_pem_base64_decode_char(c)` — A-Z/a-z/0-9/+/ 映射到 0-63
  - Base64 解码：4 字符 → 3 字节（c1*4 + c2/16, c2%16*16 + c3/4, c3%4*64 + c4）
  - `pem_encode(data, label)` — 二进制数据 → PEM（3 字节 → 4 Base64 字符，64 字符/行）
  - `_pem_base64_encode_char(n)` — 0-63 → A-Z/a-z/0-9/+/=
  - `pem_get_label()` — 返回解析的 label（CERTIFICATE / RSA PRIVATE KEY 等）
  - `pem_load(path)` — VFS 读取文件 → pem_parse
  - `pem_selftest()` — "-----BEGIN TEST-----\nSGVsbG8=\n-----END TEST-----\n" → 解码 "Hello"
  - PEM_BUF=0xFF0000（16711680），64 KB 解码缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`pem_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `pem parse <data>` / `pem load <path>` / `pem show` / `pem label` / `pem test`

## Iteration 199 — asn1.hl：ASN.1 DER 编码/解码

- **`bare-kernel/hl/asn1.hl`** 新增（~290 行）
  - ASN.1（Abstract Syntax Notation One）+ DER（Distinguished Encoding Rules）
  - 用途：X.509 证书、SNMP、LDAP、PKCS 标准
  - TLV 结构：Tag（类型）+ Length（长度）+ Value（值）
  - 长度编码：短形式（0-127 直接）、长形式（128+字节数，后跟多字节长度）
  - `asn1_encode_integer(val)` — INTEGER 标签（0x02）+ 字节序列（大端序）
  - `asn1_encode_octet_string(data)` — OCTET STRING 标签（0x04）+ 字节数据
  - `asn1_encode_null()` — NULL 标签（0x05）+ 长度 0
  - `asn1_encode_boolean(val)` — BOOLEAN 标签（0x01）+ 0x00/0xFF
  - `asn1_encode_sequence_start/end(pos)` — SEQUENCE 标签（0x30）+ 内容，延迟长度填充
  - `asn1_parse_tag/length/integer/octet_string` — 解析 TLV 结构
  - `asn1_decode(data)` — 遍历 DER 编码数据，输出类型 + 值描述
  - `asn1_get_hex()` — 编码结果转十六进制字符串
  - `asn1_selftest()` — 编码 int(42) + str("hi") + null → "02012a04026869" + "0500"
  - ASN1_BUF=0xFE0000（16646144），64 KB 编码/解码缓冲区
  - 标签常量：BOOLEAN=1, INTEGER=2, BIT_STRING=3, OCTET_STRING=4, NULL=5, OID=6, SEQUENCE=48
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`asn1_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `asn1 int <n>` / `asn1 str <text>` / `asn1 null` / `asn1 decode <hex>` / `asn1 test`

## Iteration 198 — uuencode.hl：UUencode/UUdecode 二进制-文本编码

- **`bare-kernel/hl/uuencode.hl`** 新增（~250 行）
  - UUencode 历史编码格式：3 字节 → 4 ASCII 字符（每字符 6 位，base 32+）
  - 格式：`begin <mode> <filename>` / 长度字符 + 编码行（每行最多 60 字符）/ ` (backtick 空行) / `end`
  - `uu_encode(data, filename)` — 分块编码，长度字符=32+字节数，6 位拆分 → ASCII 32+
  - `uu_decode(data)` — 逐行解析，长度字符→字节计数，4 字符→3 字节重组
  - `_uu_enc_char(n)` / `_uu_dec_char(c)` — 6 位值 ↔ ASCII 32+（纯整数模运算，无位运算）
  - `uu_get_result()` — 提取缓冲区内容为字符串；`uu_load_encode(path, fname)` — VFS 文件编码
  - `uu_selftest()` — "Cat" → 编码 → 解码 → 验证往返
  - UU_BUF=0xFD0000（16580608），64 KB 编码/解码缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`uu_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `uu encode <text> <filename>` / `uu decode <text>` / `uu show` / `uu test`

## Iteration 197 — quoted_printable.hl：Quoted-Printable MIME 编码

- **`bare-kernel/hl/quoted_printable.hl`** 新增（~200 行）
  - RFC 2045 Quoted-Printable：7 位 ASCII 安全传输 8 位数据（MIME content-transfer-encoding）
  - 编码规则：非打印字符（包括 `=`）→ `=XX`（十六进制）；行长度限制 76 字符（软换行 `=\r\n`）
  - `qp_encode(data)` — 逐字节扫描，`_qp_is_printable(c)` 判断 → 直通 / 转义 `=XX`
  - `qp_decode(data)` — 逐字符解析，`=XX` → 字节值，`=\r\n` → 软换行（跳过）
  - `_qp_hex_digit(n)` / `_qp_from_hex(c)` — 十六进制字符转换（0-9/A-F/a-f）
  - `qp_get_result()` — 从缓冲区提取结果字符串；`qp_load_encode(path)` — VFS 文件编码
  - `qp_selftest()` — "Hello=World" → "Hello=3DWorld" → 解码 → 验证往返
  - QP_BUF=0xFC0000（16515072），64 KB 编码/解码缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`qp_init()`
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `qp encode <text>` / `qp decode <text>` / `qp show` / `qp test`

## Iteration 196 — cpio.hl：CPIO 归档格式解析器/提取器

- **`bare-kernel/hl/cpio.hl`** 新增（~230 行）
  - CPIO（Unix 归档格式，initramfs 使用）；支持 "newc"（SVR4）格式
  - 格式：110 字节 ASCII 十六进制头（magic 070701）+ 文件名 + 对齐 + 数据 + 4 字节对齐
  - `_cpio_parse_hex(buf, offset, len)` — ASCII 十六进制 → 整数（逐字符 *16）
  - `_cpio_align4(n)` — 4 字节对齐（n + (4 - n%4)）
  - `cpio_parse_buf()` — 逐条目解析：magic 验证 → 提取 inode/mode/size/namesize → 文件名提取 → 偏移计算
  - TRAILER!!! 条目标记归档结束；parallel arrays 存储 name/size/mode/offset（CPIO_MAX=64）
  - `cpio_load(path)` — VFS 读取归档到缓冲区 → 调用 `cpio_parse_buf()`
  - `cpio_extract(idx, dest)` / `cpio_extract_all(dir)` — 从缓冲区偏移提取数据 → VFS 写入
  - `cpio_selftest()` — 构造简单 CPIO 头部 + "test.txt" → 解析验证
  - CPIO_BUF=0xFB0000（16449536），64 KB 归档缓冲区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`cpio_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `cpio load <path>` / `cpio list` / `cpio extract <idx> <dest>` / `cpio clear` / `cpio test`

## Iteration 186 — syslog_srv.hl：UDP syslog 远端日志服务

- **`bare-kernel/hl/syslog_srv.hl`** 新增（~230 行）
  - RFC 3164 / RFC 5424 混合解析：`<PRI>` 提取 + facility/severity 解码
  - SLSRV_MAX=64 槽环形缓冲（parallel arrays），SLSRV_BUF=0xF00000
  - `_slsrv_parse(raw)` → [pri, ts, hostname, body]（body 截断 160 字符）
  - `syslog_srv_on_recv(data)` — UDP 回调入槽 → klog 输出
  - `syslog_srv_tick()` — 主循环轮询 UDP 514 缓冲区
  - `syslog_srv_list(n)` — 从 head 反向输出最近 n 条（facility.severity 格式）
  - `syslog_srv_clear/status` — 清空 + 状态信息
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`syslog_srv_init()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `syslogd` / `syslogd start/stop/clear/status` / `syslogd last <n>`

## Iteration 185 — cbor.hl：CBOR 紧凑二进制编码

- **`bare-kernel/hl/cbor.hl`** 新增（~270 行）
  - RFC 7049 CBOR；initial byte = major_type<<5 | addl_info
  - `_cbor_encode_head(major, val)` — 内联值(0-23)/1B/2B/4B 分支（纯整数，无位运算）
  - 支持：uint / negint / bstr / tstr / array_hdr / map_hdr / bool / null
  - `cbor_get_result()` → 十六进制字符串；`cbor_encoded_len()` → 字节数
  - `cbor_decode_hex(hexstr)` → 递归解析 → 人类可读描述字符串
  - `cbor_selftest()` → 编码 uint(42)+"hi"+true+null → 验证十六进制
  - CBOR_BUF=0xEF0000（4 KB），上半区 2048B 用于解码临时区
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`cbor_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `cbor uint/neg/str/bool/null/hex/test`

## Iteration 184 — ftp.hl：FTP 文件传输客户端

- **`bare-kernel/hl/ftp.hl`** 新增（~270 行）
  - RFC 959 FTP 客户端；被动模式（PASV）数据连接
  - `_ftp_pasv_parse(resp)` — 解析 "227 (h1,h2,h3,h4,p1,p2)" → ip+port 数组
  - `ftp_connect(host)` — TCP 连接端口 21，等待 "220" 问候
  - `ftp_auth(id, user, pass)` — USER→331→PASS→230→TYPE I→200 序列
  - `ftp_list(id, path)` — PASV + LIST，排水数据连接，等待 226
  - `ftp_get(id, remote, local)` — PASV + RETR，写入 VFS；FTP_BUF=0xEE0000（64 KB）
  - `ftp_put(id, local, remote)` — VFS 读 + PASV + STOR，逐字节发送
  - `ftp_pwd/cwd/quit`；FTP_MAX=2 会话
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`ftp_init()`
- **`bare-kernel/hl/shell.hl`** 新增 8 条命令：
  - `ftp connect/auth/ls/get/put/pwd/cd/quit`

## Iteration 183 — lz4.hl：LZ4 块压缩编解码

- **`bare-kernel/hl/lz4.hl`** 新增（~310 行）
  - LZ4 块格式：token(1B) + 扩展字节 + 字面量 + 2B 偏移 + 匹配段
  - 4096 槽哈希表（LZ4_HASH=0xED0000，4B/槽）— 纯整数算术哈希
  - `lz4_compress_mem(src, slen, dst)` — 贪心最长匹配，回溯至锚点
  - `lz4_decompress_mem(src, slen, dst, dlim)` — 逐字节 token 解析 + 重叠匹配拷贝
  - `lz4_compress_file/decompress_file` — VFS 读写，打印压缩比
  - `lz4_selftest()` — 60B 重复模式 → 压缩 → 解压 → 逐字节验证
  - LZ4_IN_BUF=0xEB0000, LZ4_OUT_BUF=0xEC0000（各 64 KB）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`lz4_init()`
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：`lz4c <in> <out>` / `lz4d <in> <out>` / `lz4test`

## Iteration 182 — mqtt.hl：MQTT 3.1.1 发布/订阅客户端

- **`bare-kernel/hl/mqtt.hl`** 新增（~310 行）
  - MQTT 3.1.1 可变长度字段编码（纯整数模/除法，无位运算）
  - CONNECT 包：协议名 "MQTT" + 版本 4 + CleanSession + keepalive=60s + 客户端 ID
  - PUBLISH QoS 0：固定头 0x30 + 可变长度 + 2B 主题长度 + 主题 + 载荷
  - SUBSCRIBE：0x82 + 包 ID + 主题列表 + QoS 0
  - UNSUBSCRIBE / PINGREQ / DISCONNECT
  - `mqtt_tick()`：每 5000 tick 自动发送 PINGREQ；排水 TCP RX 缓冲区中 PUBLISH 包
  - MQTT_MAX=4 个并发连接；MQTT_BUF=0xEAC000
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`mqtt_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `mqtt connect <host> <port> <cid>` / `mqtt pub <id> <topic> <payload>`
  - `mqtt sub <id> <topic>` / `mqtt unsub <id> <topic>` / `mqtt ping <id>` / `mqtt quit <id>` / `mqtt`

## Iteration 181 — imap.hl：IMAP4rev1 邮件读取客户端

- **`bare-kernel/hl/imap.hl`** 新增（~270 行）
  - RFC 3501 IMAP4rev1；自动递增命令标签（A001..A999）
  - `imap_connect(host, port)` — TCP 连接到邮件服务器（143 明文 / 993 TLS）
  - `imap_login(id, user, pass)` — 轮询 200 tick 等待 "tag OK" 响应
  - `imap_select(id, mailbox)` — 解析 `* N EXISTS` 获取邮件数量
  - `imap_list(id)` — LIST "" * 列举邮件夹
  - `imap_fetch(id, from, to)` — FETCH FLAGS BODY[HEADER.FIELDS (FROM SUBJECT DATE)]
  - `imap_logout(id)` / `imap_tick()` — 排水 `* BYE` 主动断连
  - IMAP_MAX=4 会话；IMAP_BUF=0xE9C000（4 KB）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`imap_init()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `imap connect/login/select/list/fetch/logout`

## Iteration 180 — ui_notepad.hl：图形化多行文本编辑器

- **`bare-kernel/hl/ui_notepad.hl`** 新增（~270 行）
  - 窗口 640×460；行数组最多 200 行（NOTEP_MAX_LINES）
  - 行号 gutter（40px）+ 光标（蓝色 2px 竖线）+ 状态栏（行/列/modified）
  - 键盘：可打印字符插入 / Enter 分行 / Backspace 合并行 / 方向键 / Home/End
  - Ctrl+S 保存至 VFS；Esc 关闭；鼠标点击定位光标
  - `_notep_insert_line/delete_line`：O(n) 行数组移位操作
  - NOTEP_BUF=0xE5C000（64 KB）读写缓冲
- **`bare-kernel/hl/wm.hl`** 接入：draw / key（仅焦点窗口）/ click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 14 号图标 `UIDSK_APP_NOTEPAD`，标签 "Note"
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：`notepad` / `notepad <path>`

## Iteration 179 — semaphore.hl：POSIX 命名计数信号量

- **`bare-kernel/hl/semaphore.hl`** 新增（~170 行）
  - SEM_MAX=16；并行平坦数组 sem_active/names/vals/max_vals/waiters
  - `sem_open(name, val)` — 存在则返回已有 id，否则分配新槽
  - `sem_wait(id)` — 非阻塞：val>0 则减一返回 0，否则返回 -1（EAGAIN）
  - `sem_timedwait(id, ticks)` — 自旋等待直到超时，计数 waiters
  - `sem_post(id)` — 增一并返回新值
  - `sem_destroy(id)` — 有等待者时打印警告后销毁
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`sem_init_subsystem()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `sem list` / `sem create <name> <val>` / `sem wait <id>`
  - `sem post <id>` / `sem value <id>` / `sem destroy <id>`

## Iteration 178 — traceroute.hl：逐跳路由追踪

- **`bare-kernel/hl/traceroute.hl`** 新增（~170 行）
  - UDP 探测包（40 字节），目标端口 33434+seq，本地端口 17071
  - 每跳递增 TTL；等待 ICMP type=11（TTL 超时）或 type=3（目标不可达）
  - 超时 200 ticks（2 s）→ 输出 `* * *`
  - `_trace_build_probe(seq)` → 40 字节数组（含 TTL 字段）
  - `traceroute_on_recv(data)` UDP 回调：解析 ICMP 类型 + 发送方 IP
  - `traceroute_host(host, max_hops)` → 多行跳表字符串
  - TRACE_MAX_HOPS=30
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`traceroute_init()`
- **`bare-kernel/hl/shell.hl`** 新增 1 条命令：`traceroute <host> [max_hops]`

## Iteration 177 — ui_taskman.hl：图形化任务管理器

- **`bare-kernel/hl/ui_taskman.hl`** 新增（~240 行）
  - 窗口 580×400；扫描 task.hl 任务表（UITM_TASK_TBL=0x880000，64 槽）
  - 列：PID / Name / State / Pri / Ticks / Mem KB
  - 状态颜色：运行=绿 / 阻塞=黄 / 僵尸=红
  - 每 50 tick（~0.5 s）`uitaskman_tick()` 自动刷新
  - 'K' 键向选中进程发送 SIGKILL；'R' 手动刷新；↑↓ 滚动选行
  - 点击行选中进程；底部状态栏显示进程总数
- **`bare-kernel/hl/wm.hl`** 接入：draw+tick / key / click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 13 号图标 `UIDSK_APP_TASKMAN`，标签 "Tasks"
- **`bare-kernel/hl/shell.hl`** 新增 1 条命令：`taskman`

## Iteration 176 — ping.hl：ICMP Echo 网络诊断

- **`bare-kernel/hl/ping.hl`** 新增（~150 行）
  - 64 字节 ICMP Echo 包结构（Type/Code/Checksum/ID/Seq + 56 字节数据）
  - 纯算术 16-bit 一补数校验和：`65535 - (sum % 65536 + sum / 65536)` 折叠进位
  - `ping_once(ip_arr)` → RTT ticks（100 Hz → 10 ms/tick）；超时 300 ticks
  - `ping_host(host, count)` → 完整统计字符串（sent/recv/loss% + min/avg/max ms）
  - `ping_on_recv(data)` 由 UDP 栈回调（port 17070）
  - PING_PORT=7（ECHO 服务），PING_LPORT=17070
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`ping_init()`
- **`bare-kernel/hl/shell.hl`** 新增 1 条命令：`ping <host> [count]`

## Iteration 175 — csv.hl：CSV 解析器 / 写入器（RFC 4180）

- **`bare-kernel/hl/csv.hl`** 新增（~210 行）
  - 支持带引号字段（`""` 转义）、自定义分隔符、`\r\n` → `\n` 规范化
  - 存储：`csv_rows[]`（原始行字符串数组），按需解析（`_csv_parse_row`）
  - `_csv_parse_row(row)` → HL 字段数组（处理引号、逐字段）
  - `_csv_build_row(fields)` → 重建 CSV 行字符串（按需加引号）
  - 缓冲区：CSV_BUF=0xE4C000（64 KB）；最多 256 行 × 32 列
  - `csv_load/save`：VFS 文件 I/O；`csv_get/set`：字段读写；`csv_head/col_names`：显示辅助
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`csv_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `csv load <path>` / `csv list [n]` / `csv get <row> <col>`
  - `csv set <row> <col> <val>` / `csv save <path>` / `csv cols`

## Iteration 174 — profiler.hl：内核性能分析器

- **`bare-kernel/hl/profiler.hl`** 新增（~230 行）
  - **命名计数器**：最多 32 个命名事件计数器；`prof_inc(name)` 创建或递增
  - `prof_report()`：按计数降序冒泡排序后格式化输出
  - `prof_top(n)`：Top-N 计数器（线性选择算法）
  - **tick 采样环**：64 槽圆形缓冲区；`prof_sample()` 存储当前 get_ticks()
  - **Span 计时器**：最多 8 个命名跨度；`prof_span_start/stop` 记录累计时钟 tick 和命中次数
  - `prof_span_report()`：输出总耗时 / 命中次数 / 平均
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`prof_init()`
- **`bare-kernel/hl/shell.hl`** 新增 8 条命令：
  - `prof report` / `prof reset` / `prof top <n>` / `prof inc <name>`
  - `prof get <name>` / `prof spans` / `prof sample` / `prof ring`

## Iteration 173 — ini.hl：INI 配置文件解析器

- **`bare-kernel/hl/ini.hl`** 新增（~230 行）
  - 支持 `[section]` / `key = value` / `;#` 注释 / 空行
  - 存储：平坦并行数组 ini_secs/keys/vals，最多 64 条目
  - `_ini_trim(s)`：去除行首尾空白/制表符
  - `ini_load(path)`：VFS 读取 → 逐行解析 → 填充数组
  - `ini_save(path)`：按 section 分组 → 生成输出字符串 → VFS 写入
  - `ini_get/set/delete/list`：O(n) 线性查找，索引覆盖更新
  - 缓冲区：INI_BUF_ADDR=0xE39000（64 KB）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`ini_init()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `ini load <path>` / `ini list` / `ini get <sec> <key>`
  - `ini set <sec> <key> <val>` / `ini save <path>` / `ini del <sec> <key>`

## Iteration 172 — base64.hl：Base64 编解码（RFC 4648）

- **`bare-kernel/hl/base64.hl`** 新增（~220 行）
  - 纯算术位操作仿真（无 HL 位运算）：`b1 / 4` = `b1 >> 2`，`b1 % 4 * 16` = `(b1 & 3) << 4` 等
  - 64 元素字母表数组 B64_ALPHA（A-Z a-z 0-9 + /）
  - `b64_encode_file(src, dst)` / `b64_decode_file(src, dst)`：VFS 文件编解码
  - `b64_encode_str(text)` / `b64_decode_str(b64)`：HL 字符串直接编解码
  - `_b64_dec_char(c)`：ASCII → 6-bit 值（对 '=' padding 返回 -1）
  - 缓冲区：B64_IN_BUF=0xE1C000，B64_OUT_BUF=0xE2C000（各 64 KB）
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`b64_init()`
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `b64encode <src> <dst>` / `b64decode <src> <dst>` / `b64str <text>`

## Iteration 171 — ui_clock.hl：数字时钟小部件

- **`bare-kernel/hl/ui_clock.hl`** 新增（~230 行）
  - 浮动窗口 200×80，右上角定位（UICLOCK_X=984，UICLOCK_Y=40）
  - 大字 HH:MM:SS 时间行（`ntp_get_time()` → `_uiclock_decode`）+ 日期行 YYYY-MM-DD
  - 状态栏：`[h]24h` 切换 + 闹钟显示
  - 'h' 键切换 12h/24h 模式；Esc 关闭
  - `uiclock_tick()` 由 wm compositor 每帧调用，秒变化时自动 redraw
  - `uiclock_set_alarm(h, m)`：整点触发 `notify_show` + klog
  - `_uiclock_decode(unix)`：unix 时间戳 → [y,m,d,h,min,sec]，完整闰年支持
- **`bare-kernel/hl/wm.hl`** 接入：draw+tick / key / click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 12 号图标 `UIDSK_APP_CLOCK`，标签 "Clock"
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `clock` / `clock close` / `clock time` / `clock alarm <HH> <MM>`

## Iteration 170 — diff.hl：LCS 统一差异算法

- **`bare-kernel/hl/diff.hl`** 新增（~280 行）
  - LCS 动态规划（128×128 表，16KB，展平 1-D HL 数组）
  - 反向追踪生成编辑序列（" " context / "-" remove / "+" add）
  - 分块输出：`@@ -A,B +C,D @@` hunk 格式，3 行上下文
  - DIFF_BUF_A=0xDFA000（64 KB）+ DIFF_BUF_B=0xE0A000（64 KB）读文件缓冲
  - 每文件最多 128 行（`DIFF_MAX_LINES`）
  - `diff_files(path_a, path_b)` / `diff_strings(a, b)` / `diff_stat(a, b)`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`diff_init()`
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `diff <pathA> <pathB>` / `diffstat <pathA> <pathB>` / `diffstr <textA> <textB>`

## Iteration 169 — sqlite.hl：嵌入式内存关系数据库

- **`bare-kernel/hl/sqlite.hl`** 新增（~300 行）
  - DB_MAX_TABLES=8；并行平坦数组（db_active/names/schemas/data/counts）
  - 行格式：Tab 分隔字段；行间换行符分隔
  - `_db_split(s, delim)` 通用字符串分割 → HL 数组
  - `_db_col_idx(schema, col)` / `_db_row_val(row, idx)` 字段定位
  - 完整 CRUD：`db_create` / `db_drop` / `db_insert` / `db_select_all`
    / `db_select_where` / `db_delete_where` / `db_update_where`
    / `db_count` / `db_schema` / `db_list`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`db_init()`
- **`bare-kernel/hl/shell.hl`** 新增 9 条命令：
  - `db list` / `db create <name> <schema>` / `db insert <name> <row>`
  - `db select <name>` / `db where <name> <col> <val>`
  - `db delete <name> <col> <val>` / `db drop <name>` / `db schema <name>` / `db count <name>`



- **`bare-kernel/hl/compress.hl`** 新增（~260 行）
  - 双算法：RLE（逃逸字节 0xFF）+ LZSS（256 字节滑动窗口）
  - 缓冲区：COMP_IN_BUF=0xDE8000（64 KB）+ COMP_OUT_BUF=0xDF8000（64 KB）
  - RLE：run ≥ 3 时编码为 `0xFF count byte`；0xFF 字面量编码为 `0xFF 0xFF`
  - LZSS：每 8 个 token 一个 flag 字节；bit=0=literal，bit=1=back-ref（offset u8 + length u8）
  - `compress_stat(path)`：统计原始大小 + RLE 估计压缩率
  - `_comp_read_file/write_file`：VFS I/O 封装
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `compress <rle|lz> <src> <dst>` / `decompress <rle|lz> <src> <dst>` / `compstat <path>`

## Iteration 167 — ui_calendar.hl：月历应用

- **`bare-kernel/hl/ui_calendar.hl`** 新增（~310 行）
  - 440×380 窗口，7 列 × 6 行网格（Zeller 公式计算首日星期）
  - 工具栏：← Prev | 月名年份 | Next →
  - 今日高亮（accent 色，由 `ntp_get_time()` 获取）
  - 事件存储：最多 32 条（day/month/year/text），有事件日期显示小圆点
  - 点击日期格 → 选中；底部面板显示当天事件列表
  - 键盘：Esc=关闭，←/→=换月，'t'=跳回今日
  - 闰年支持（4/100/400 规则）；`_uical_dow_first` 用 Zeller 变换
- **`bare-kernel/hl/wm.hl`** 接入：draw / key / click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 11 号图标 `UIDSK_APP_CALENDAR`，标签 "Cal"
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `calendar` / `cal` / `cal next` / `cal prev` / `cal today`
  - `cal add <day> <text>` / `cal goto <month> <year>`

## Iteration 166 — irc.hl：IRC 客户端（RFC 1459）

- **`bare-kernel/hl/irc.hl`** 新增（~230 行）
  - IRC_MAX=4 并发会话，默认端口 6667
  - 5 个会话状态：FREE → CONN → REGISTERED → JOINED → ERR
  - IRC 消息解析器：`_irc_get_command/trailing/params` + `_irc_prefix_nick`
  - 自动响应 PING：检测到 `PING` 立即发送 `PONG :<server>`
  - 001 响应 → 状态升级至 REGISTERED
  - PRIVMSG 接收 → 格式化 `<nick> text` 并写入 `irc_last_msg[id]` + klog
  - JOIN 确认 → 状态升级至 JOINED，记录频道名
  - `_irc_process_resp` 按 `\r\n` 分割多行批量处理
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`irc_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `irc` / `irc connect <host> [port]` / `irc reg <id> <nick> <user>`
  - `irc join <id> <#chan>` / `irc say <id> <target> <msg>` / `irc recv <id>`
  - `irc part <id>` / `irc quit <id>` / `irc status <id>`



## Iteration 165 — pop3.hl：POP3 邮件接收客户端（RFC 1939）

- **`bare-kernel/hl/pop3.hl`** 新增（~220 行）
  - POP3_MAX=4 并发会话，POP3_BUF=0xDE0000（8 KB/会话响应缓冲）
  - 6 个会话状态：FREE → CONN → AUTH → READY → BUSY → ERR
  - `pop3_connect(host, port)`：DNS 解析 + TCP 连接
  - `pop3_auth(id, user, pass)`：USER + PASS 命令序列
  - `pop3_stat(id)` → `[count, total_bytes]`：解析 "+OK N M" 响应
  - `pop3_list(id)`：LIST 命令 → 邮件编号+大小列表
  - `pop3_retr(id, n)`：RETR n → 剥离 "+OK" 前缀 + ".\r\n" 尾
  - `pop3_dele(id, n)`：DELE 标记删除
  - `pop3_tick()`：轮询待处理响应，错误写入 klog(WARN)
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`pop3_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `pop3` / `pop3 connect <host> <port>` / `pop3 auth <id> <user> <pass>`
  - `pop3 list <id>` / `pop3 get <id> <n>` / `pop3 quit <id>`

## Iteration 164 — ui_hexedit.hl：十六进制编辑器

- **`bare-kernel/hl/ui_hexedit.hl`** 新增（~320 行）
  - 620×440 窗口，22 行 × 16 字节/行 = 352 字节可见
  - 布局：8 位偏移 | 16 对十六进制 | 16 字符 ASCII 列
  - VFS 文件加载：4 KB 页面至 HEXED_BUF=0xDD0400
  - 导航：方向键（±1 字节）/ PgUp/PgDn（±352 字节）/ Home/End（行首/尾）
  - 编辑模式：Tab 切换 view/edit；半字节输入（高/低 nibble）；Ctrl+S 保存到 VFS
  - 工具栏：Open / Save / Close / Edit（active 高亮）；未保存指示
  - 点击内容区：按行列坐标移动光标
- **`bare-kernel/hl/wm.hl`** 接入：draw / key / click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 10 号图标 `UIDSK_APP_HEXEDIT`，标签 "Hex"
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：`hexedit` / `hexedit <path>`

## Iteration 163 — ntp.hl 完整实现 + tar.hl：TAR 归档读取

- **`bare-kernel/hl/ntp.hl`** 升级（stub → 完整 SNTP 实现）
  - 删除注释存根，改用 HL 字节数组构建 48 字节 NTP 请求
  - `_ntp_build_request()`：LI=0, VN=4, Mode=3 → 0x23 + 44 字节零
  - `ntp_on_recv(data)`：UDP 回调，设置 `ntp_resp_ready + ntp_resp_data`
  - `ntp_sync(host)`：dns_resolve → udp_bind → udp_send → 轮询回调 → 解析 offset 40 大端 u32
  - `ntp_format_time(unix)`：Unix 时间戳 → "YYYY-MM-DD HH:MM:SS"（含闰年处理）
  - `ntp_get_time()`：`last_unix + (get_ticks() - last_tick) / 100`
- **`bare-kernel/hl/tar.hl`** 新增（~260 行）
  - POSIX ustar 格式；512 字节块；一次读取一块（VFS + TAR_BUF=0xDD0000）
  - `_tar_oct(addr, len)`：八进制 ASCII 字段解析
  - `_tar_is_ustar(addr)`：验证 offset 257 "ustar" 魔数
  - `_tar_fullname(addr)`：合并 prefix[155] + "/" + name[100]
  - `tar_list(path)` / `tar_cat(tar_path, filename)` / `tar_extract(tar_path, dest)` / `tar_info(path)`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`ntp_init()`（已含 pop3_init）
- **`bare-kernel/hl/shell.hl`** 新增 3+4=7 条命令：
  - `ntp sync <host>` / `ntp time` / `ntp status`
  - `tar list <path>` / `tar cat <path> <file>` / `tar extract <path> <dest>` / `tar info <path>`



## Iteration 162 — ui_image.hl：BMP 图像查看器

- **`bare-kernel/hl/ui_image.hl`** 新增（~343 行）
  - 480×380 图形窗口，图像区 448×320，工具栏 32px，状态栏 16px
  - BMP 格式解析：小端 u16/u32/i32 读取；"BM" 签名校验；仅支持 24/32-bit 无压缩
  - 行 stride = `ceil(bpp*width/32)*4`；正 height → 底部优先行顺序
  - `_bmp_pixel(x,y)` 返回 0xFFRRGGBB；zoom=1 → `vesa_putpixel`，zoom=2 → `vesa_fill_rect` 2×2
  - 加载缓冲：UIIMG_LOAD_BUF=0x9D0000（4 MB），通过 `vfs_read` 一次性读入
  - 工具栏按钮：Open / Close / 1x（active 高亮）/ 2x（active 高亮）
  - 键盘：Esc=关闭，'1'=1x zoom，'2'=2x zoom
  - 公开 API：`uiimg_open/close/draw/key/click/load/is_open`
- **`bare-kernel/hl/wm.hl`** 接入：`wm_draw_all` + `wm_key_dispatch` + `wm_mouse_click`
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 9 号图标 `UIDSK_APP_IMAGE`，标签 "Img"
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：
  - `imgview <path.bmp>`：打开查看器并加载 BMP
  - `imgview zoom <1|2>`：切换缩放级别

## Iteration 161 — cron.hl：内核定时任务调度器

- **`bare-kernel/hl/cron.hl`** 新增（~220 行）
  - CRON_MAX=16 槽位，100 Hz tick 时间基准（interval_secs × 100 = ticks）
  - 每槽位 7 个状态数组：active / enabled / repeat / interval / next / cmd / fire_cnt
  - `cron_tick()`：遍历所有槽位，`get_ticks() >= cron_next[i]` 时调用 `shell_handle(cmd)`
  - 一次性任务：触发后自动移除；周期任务：重新设定 `now + interval`
  - `cron_setup_system_jobs()`：注册 4 个系统任务（date 30s / dmesg 60s / ws tick 120s / telnet tick 60s）
  - 便捷包装：`cron_add_secs(cmd, secs, repeat)` → `cron_add(cmd, secs*100, repeat)`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`cron_init()` + `cron_setup_system_jobs()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `cron` / `cron add <secs> <cmd>` / `cron once <secs> <cmd>`
  - `cron rm <id>` / `cron en <id>` / `cron dis <id>`

## Iteration 160 — smtp.hl：SMTP 邮件客户端（RFC 5321）

- **`bare-kernel/hl/smtp.hl`** 新增（~257 行）
  - SMTP_MAX=4 并发会话，SMTP_BUF=0x9C0000（16 KB 响应缓冲）
  - 9 个会话状态：FREE→CONN→READY→AUTH→MAIL→RCPT→DATA→DONE→ERR
  - `smtp_b64_encode(s)`：三字节组 → 6-bit 索引 → BASE64 字符，支持 = 填充
  - `smtp_send_email(id,from,to,subj,body)`：完整 MAIL FROM + RCPT TO + DATA + RFC 5322 头 + body + `\r\n.\r\n`
  - `smtp_auth(id,user,pass)`：AUTH LOGIN + base64 用户名/密码
  - `smtp_tick()`：轮询 TCB RX 缓冲，响应码 ≥500 时写入 klog(ERROR)
  - `smtp_status/list`：格式化会话状态字符串
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`smtp_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `smtp` / `smtp connect <host> <port>` / `smtp auth <id> <user> <pass>`
  - `smtp send <id> <from> <to> <subj> <body>` / `smtp quit <id>`


- H-L 总行数：`~47,800`（根 10,044 + 内核 ~37,756）
- 内核模块：`130`（编译产出 1,700+ 函数 / 2,003+ 符号）
- `kernel_entry.hl`：`9,428` 行
- `hl-bootstrap.hl`：`4,306` 行，`208` 函数
- `stdlib.hl`：`1,385` 行，`143` 函数
- `kinterp.hl`：`~1,280` 行
- Shell 命令（`shell.hl` if cmd ==）：`75`
- `scripts/*.ps1`：`28`（9,729 行）
- 构建/测试主入口：`hl-bootstrap.cmd test`
- 最近完成功能迭代：`133`（ext4真实读路径 + GPU桥接 + 词法器修复 + 字体光标）

## Iteration 140 — kernel_init修正+signal集成+mmap真实分发+WM启动终端窗口+sched_tick

- **`kernel_init.hl`**: 全面修正 + 新增初始化
  - 模块计数 130→132
  - Phase 2: `mmap_init()` 新增（demand paging COW mmap）
  - Phase 4: `mlfq_init()` + `signal_init_subsystem()` 新增（MLFQ调度器 + 信号子系统）
  - Phase 6: `wm_init()` 新增（窗口管理器 + 桌面chrome）
  - Phase 9: `syscall_msr_setup(0)` 新增（STAR/LSTAR/FMASK MSR配置）
  - 汇总字符串 130→132
  - 启动后: `wm_open_terminal_window()` 打开图形终端窗口
- **`signal.hl`**: 新增两个关键函数
  - `signal_init_subsystem()`: 清零 64*512=32768 字节处理器表
  - `signal_check_task(task_idx)`: 调度tick调用，处理SIGKILL/SIGTERM默认行为
- **`syscall.hl`**: 修复 + 新增
  - `SYS_MMAP(16)`: 从 `page_alloc()` 改为 `sys_mmap()` (lazy, COW-capable)
  - `SYS_MUNMAP(17)`: 改为 `sys_munmap()` (properly frees region table entry)
  - 新增: `SYS_MPROTECT(19)` → `sys_mprotect()`
  - 新增: `SYS_SIGNAL(85)/SYS_SIGRETURN(86)/SYS_SIGBLOCK(87)/SYS_SIGUNBLOCK(88)`
- **`sched.hl`**: 新增 `sched_tick(task_idx)`
  - 调用 `mlfq_tick` → 按需 `mlfq_demote`
  - 调用 `mlfq_check_boost`
  - 调用 `signal_check_task` — 信号与调度器集成
- **`wm.hl`**: 新增 `wm_open_terminal_window()`
  - 在桌面顶栏下方创建 640×400 终端窗口
  - 调用 `uiterm_open()` 并初始渲染



- **`syscall.hl`**: 全面增强系统调用分发
  - `SYS_WRITE(33)`: fd=1/2→serial; fd>2→`vfs_write(fd, str, len)`
  - `SYS_READ(32)`: fd=0→键盘中断; fd>0→`vfs_read(fd, buf, len)`
  - 新增: `SYS_LSEEK(62)`→`vfs_seek`, `SYS_FSTAT(63)`→fd表stat写入用户缓冲
  - 新增: `SYS_SOCKET(68)/SYS_BIND/SYS_CONNECT/SYS_ACCEPT/SYS_SENDTO/SYS_RECVFROM` → socket.hl
  - 新增: `SYS_GETUID(10)/SYS_GETGID(11)/SYS_SETUID(12)` → current_uid/gid
  - 新增: `SYS_INOTIFY_INIT(90)/ADD_WATCH(91)/RM_WATCH(92)/READ(93)/CLOSE(94)` → inotify.hl
- **`pty.hl`**: 新增高层函数
  - `pty_exec_input(id)`: 从master-to-slave缓冲读取行, 调用`shell_handle_ext()`, 回写结果
  - `pty_open_pair()`: 分配PTY对并绑定当前任务, 返回 [mfd, sfd, id]
- **`kinterp.hl`**: 改进错误报告
  - `ki_call_fn()`: 参数数量不足时 `klog()` 警告（不再默默补0）
  - `ki_parse_primary()` 未知函数: `klog()` 记录函数名而非静默返回0
- **`shell.hl`**: 新增4条命令（87 total）
  - `pty`: 显示PTY状态
  - `pty alloc`: 分配新PTY对
  - `pty info <id>`: 显示指定PTY信息
  - help中 FS Events 行增加pty命令



- **`vfs.hl`**: inotify事件钩子接入
  - `vfs_open()`: 末尾调用 `inotify_emit(path, IN_OPEN=32, path)`
  - `vfs_write()`: 写入成功后调用 `inotify_emit(path, IN_MODIFY=2, path)`
  - `vfs_mkdir()`: 创建成功后调用 `inotify_emit(path, IN_CREATE=256, path)`
  - `vfs_unlink()`: 删除成功后调用 `inotify_emit(path, IN_DELETE=512, path)`
  - `vfs_mkdir`/`vfs_unlink` 重构为先计算再返回（捕获结果判断是否需要emit）
- **`kernel_init.hl`**: Phase 5 增加 `inotify_init_subsystem()` 调用
- **`kinterp.hl`** ki_call_builtin 新增17个内置函数:
  - `vfs_read(fd,buf,len)`, `vfs_write(fd,data,len)`, `vfs_seek(fd,off,whence)`
  - `klog(level,sub,msg)`, `pipe_create()`, `pipe_write/read/available`
  - `mem_copy(src,dst,len)`, `mem_read_string(addr,max)`, `mem_write_string(addr,s)`
  - `task_count()`, `task_count_active()`, `task_list_all()`
  - `random_u32()`, `serial_readline()`, `serial_readline_noecho()`
  - `inotify_emit(path,mask,name)`, `str_len(s)`
- **`shell.hl`**: 新增4条命令（83 total）
  - `echo <text> > <file>`: O_CREAT|O_WRONLY 打开文件，vfs_write写入，vfs_close
  - `inotify`: 显示 instances/watches/queued_events 计数
  - `watch <path>`: sys_inotify_init+add_watch, 10轮轮询输出事件
  - help 更新增 FS Events 行和echo重定向说明



- **`kinterp.hl`**: else-if死码清理
  - 删除错误的 `ki_pos = ki_pos - 1`（修改了错误变量）
  - 删除无用的 `tt2`/`tv2` 变量赋值
  - 递归 `ki_exec_stmt()` 直接复用已正确指向 "if" 的 `ki_tok_idx`
- **`syslog.hl`**: 修复 + 增强
  - `klog()`: `ticks` 未定义 → `get_ticks()`
  - `dmesg()`: 解除注释，读取真实日志条目（时间戳 + 级别 + 消息）
  - `syslog_init()`: 新增初始化函数（清空缓冲区 + 首条日志记录）
- **`serial.hl`**: 新增字符串行读取函数
  - `serial_readline()`: 阻塞读一行字符串（带回显）
  - `serial_readline_noecho()`: 阻塞读一行字符串（无回显，用于密码）
- **`login.hl`**: 修复 + 启用真实输入
  - `let attempts` → `let mut attempts`（修复不可变赋值 bug）
  - 启用 `serial_readline()` / `serial_readline_noecho()` 真实读取
- **`kernel_init.hl`**: 模块数 + 登录 + 新初始化
  - 模块计数 122 → 130
  - Phase 0 新增 `syslog_init()` 调用
  - Phase 7 新增 `netfilter_init()` 调用
  - Summary 后新增 `login_prompt()` → 验证用户再进 shell
- **`netfilter.hl` + `net.hl`**: 防火墙钩子集成
  - `net_input()`: 解析 src/dst IP + port，调用 `nf_match(NF_CHAIN_INPUT,...)`
  - DROP / REJECT 提前 return 0，丢弃数据包
  - TCP UDP ICMP 均受 netfilter 过滤保护
- **`shell.hl`**: 防火墙管理命令
  - `fw`: nf_status() 快速状态
  - `firewall`: 详细规则列表（链/端口/动作/命中次数）
  - `fw allow <port>`: INPUT ACCEPT tcp dport
  - `fw block <port>`: INPUT DROP tcp dport
  - `fw flush`: 重置所有规则
  - `fw policy input|output drop|accept`: 设置默认策略
  - help 新增 Firewall 行

## Iteration 136 — task/arp/tcp补全函数 + kinterp else-if链 + shell ps/proc/mount增强

- **`task.hl`**: 新增 `task_count_active()` / `task_name(idx)` / `task_list_all()`
  - `task_count_active()`: 统计非 FREE 任务数（用于 /proc/stat）
  - `task_name(idx)`: 从 name_ptr 读取任务名，回退为 "task<N>"
  - `task_list_all()`: 返回 [[pid, state_name, name], ...] 列表
- **`arp.hl`**: 新增 `arp_table_snapshot()`
  - 遍历 `_arp_valid[]` 数组，导出所有有效条目为 [ip_str, mac_str] 列表
  - IP 转点分十进制，MAC 转 hex colon 格式
- **`tcp.hl`**: 新增 `tcp_connections_summary()`
  - 扫描 TCP_TABLE，跳过 TCP_CLOSED，格式化为多行字符串
  - 含本地/远端 ip:port、状态名、cwnd 值
- **`kinterp.hl`**: 新增 else-if 链解析
  - `if cond { } else if cond { } else { }` 完整支持
  - 条件为真时循环跳过后续所有 else-if/else 分支
  - 条件为假时检测 `else if`，递归调用 `ki_exec_stmt()` 继续判断
- **`shell.hl`**: ps/mount/proc 命令增强
  - `ps`: 改用 `task_list_all()` 格式化 PID/STATE/NAME 表格
  - `mount`: 改用 `procfs_read("/proc/mounts")` 动态显示挂载点
  - `proc`: 无参数时 `vfs_readdir("/proc")` 列目录
  - `proc <arg>`: 读取 /proc/<arg> 或绝对路径

## Iteration 135 — procfs VFS集成 + shell管道 + terminal窗口渲染

- **`procfs.hl`**: 完整重写
  - `procfs_init()`: 调用 `vfs_mount_procfs("/proc")` 真实注册为 fs_type=4 挂载点
  - `procfs_read("/proc/version")`: 版本修正 → "HicOS 6.0 (130 modules)"
  - `procfs_read("/proc/meminfo")`: 改用 `page_count_free()` 动态查实时内存
  - `procfs_read("/proc/cpuinfo")`: 循环生成每 CPU 条目（支持 SMP）
  - `procfs_read("/proc/mounts")`: 遍历 VFS mount_count/MOUNT_TABLE 动态生成
  - `procfs_read("/proc/stat")`: 读 get_ticks() + task_count_active()
  - `procfs_read("/proc/net/arp")`: 调用 arp_table_snapshot() 真实 ARP 表
  - `procfs_read("/proc/net/tcp")`: 调用 tcp_connections_summary()
  - `procfs_read("/proc/<pid>/status")`: 解析 PID → task_addr() 查内存
- **`vfs.hl`**: procfs (fs_type=4) 全面集成
  - `vfs_mount_procfs(path)`: 新增挂载函数
  - `vfs_open()`: fs_type=4 分支存路径到 fd+48 供 read 使用
  - `vfs_read()`: fs_type=4 调用 procfs_read(stored_path) 返回内容
  - `vfs_stat()`: fs_type=4 区分目录(/proc, /proc/net, /proc/self)和文件
  - `vfs_readdir()`: fs_type=4 返回 /proc 静态目录列表 + /proc/net/ + /proc/self/
  - `vfs_mkdir/unlink`: fs_type=4 返回-1（只读）
- **`vesa.hl`**: 新增 `vesa_line_addr(y)` 返回扫描行起始字节地址（terminal滚动需要）
- **`terminal.hl`**: 取消所有注释，接入真实渲染
  - `term_init()`: 调用 `wm_create_window(50,50,w,h,"Terminal",0)` 创建真实窗口
  - `term_clear()`: `vesa_fill_rect_fast` 填充窗口内容区
  - `term_putchar()`: `font_putchar(ch, px, py, fg, bg)` 逐字符渲染
  - `term_scroll_up()`: `mem_copy` 逐扫描行上移像素，清最后一行
- **`shell.hl`**: 管道操作符 + 多处修正
  - `shell_handle_pipe(pipeline)`: `|` 分割，执行左侧，对右侧 `grep/wc/head/tail` 处理
  - `_str_contains(haystack, needle)`: 子串搜索辅助函数
  - `shell_main()`: 检测 ` | ` 后分流到 `shell_handle_pipe()`
  - `cat /proc/...`: 新增 fs_type=4 分支调用 `procfs_read()` 直接返回
  - `ver` 命令: 114 → 130 模块
  - `help` 新增 Pipe: 行和 Proc: 行
  - 命令计数更新: 75 → 79 commands + pipe(|)
- **`kernel_init.hl`**: Phase 5 增加 `procfs_init()` 调用



- **`vfs.hl`**: ext4 (fs_type=3) 全面集成
  - `vfs_mount_ext4(path, ahci_port)`: 调用 ext4_init 后注册为 fs_type=3 挂载点
  - `vfs_open()`: ext4路径下解析inode号存入fd表，读取inode得文件大小
  - `vfs_read()`: fs_type=3 分支调用 ext4_read_file，读入EXT4_BLOCK_BUF返回字节数
  - `vfs_stat()`: ext4路径下读inode mode字段判断文件/目录，返回[size,type,ino,0]
  - `vfs_readdir()`: ext4路径下调用 ext4_list_dir，过滤 "." / ".."，返回名称数组
  - `vfs_mkdir()` / `vfs_unlink()`: ext4分支返回-1（只读）
- **`kinterp.hl`**: 解释器全面增强
  - `while` 循环: 移除10000次迭代硬限制，改用 `loop_running` flag，支持无限循环
  - 数组下标赋值: `arr[i] = v` 语句 (`set_at` + 变量回写) 完整实现
  - `ki_call_builtin` 扩充至 35 个内置函数:
    - 新增: `serial_print, parse_int, set_at, str_sub, str_char_at, str_from_code`
    - 新增: `str_starts_with, str_ends_with, format_hex, abs, min, max`
    - 新增: `mem_read/write_u16/u64, mem_zero, uptime_secs`
    - 新增: `vfs_open, vfs_close, vfs_stat, vfs_readdir, ext4_resolve, ext4_list_dir`
- **`shell.hl`**: 文件命令增强
  - `ls`: 改为调用 `vfs_readdir("/")` 输出文件名列表（原为 fs_list 条目计数）
  - `ls /path`: 新增带路径参数，支持列出任意目录
  - `cat /path`: ext4路径下直接调用 ext4_read_path，从EXT4_BLOCK_BUF构建字符串输出
- **`kernel_init.hl`**: Phase 7 改为调用 `vfs_mount_ext4("/", 0)` 而非直接 ext4_init



- **`ext4.hl`**: 完整实现真实磁盘读路径（原全为注释/空桩）
  - `ext4_init(ahci_port)`: 读超级块(LBA 2)、校验EF53魔数、提取block_size/inode_size/ipg/feature_incompat
  - `ext4_read_inode(inode_num)`: 读BGDT → 找inode表块 → 计算LBA → `ahci_read()` → 返回EXT4_INODE_BUF地址
  - `ext4_parse_extents(inode_addr)`: 解析extent header(魔数0xF30A) + 叶节点extent列表
  - `ext4_read_file(inode_num, max_size)`: 循环读extent → 写入EXT4_BLOCK_BUF → 返回字节数
  - `ext4_list_dir(inode_num)`: 解析线性dir entry(ino+rec_len+name_len+type+name) → 返回[name,ino,type]数组
  - `ext4_resolve(path)`: 分段解析路径 → 递归ext4_list_dir → 返回inode号
  - `ext4_read_path(path, max_size)`: 快捷接口，path→inode→file read
  - 新增固定缓冲区: 0x930000(SB) / 0x932000(BGDT) / 0x934000(inode) / 0x938000(block)
- **`kinterp.hl`**: 修复词法器关键Bug（数字+标识符扫描器）
  - 原实现: `ki_pos = ki_source_len + 1` break后 `ki_pos - ki_source_len - 1 + start = start`，扫描结束后ki_pos回到token起始位置，导致无限重扫
  - 修复: 改用独立 `scan_num`/`scan_id` flag控制的 while 循环，`ki_pos` 正确停在第一个非法字符
- **`vesa.hl`**: 新增GPU桥接 + 快速填充
  - `vesa_fill_rect_fast(x,y,w,h,color)`: 每行用 `mem_set32()` 整行写入，替代逐像素循环
  - `vesa_gpu_mode(gpu_fb_addr, gpu_w, gpu_h)`: 将 vesa_fb_addr 指向 GPU_FB_ADDR，一行完成 GPU/VESA 桥接
  - `vesa_hline()` 改为调用 `vesa_fill_rect_fast()`（性能优化）
- **`wm.hl`**: `wm_draw_all()` 末尾增加 `if gpu_initialized == 1 { gpu_flip(); }`，所有帧自动推送到VirtIO-GPU显示
- **`font.hl`**: 新增文本光标 + 终端输出接口
  - `font_sync_fb()`: 从当前vesa全局变量同步字体渲染器参数
  - `font_cur_col/row`, `font_fg/bg` 全局光标状态
  - `font_putc(ch)`: 单字符输出 + 光标推进 + 自动换行 + 自动滚屏
  - `font_print(s)` / `font_println(s)`: 字符串输出至光标位置
  - `font_scroll_up()`: 全屏上滚一行 + 清底行
- **`kernel_init.hl`**: 初始化序列升级
  - Phase 6 后增加 `font_sync_fb()`
  - Phase 7 增加: VirtIO-GPU检测/初始化/桥接序列 + `ext4_init(0)` 挂载根文件系统
  - GPU init成功后额外调用 `font_sync_fb()` 重绑字体到GPU帧缓冲
- **`shell.hl`**: 新增 `gpu`（显示GPU状态）和 `ext4`（列出根目录）命令 → 75条命令



- **`gpu.hl`**: 完整实现 VirtIO-GPU 2D命令提交管线
  - `gpu_detect()`: PCI扫描找到 VirtIO-GPU (0x1AF4:0x1050)
  - `gpu_init()`: VirtIO设备初始化 → GET_DISPLAY_INFO → resource → backing → scanout → flush
  - `gpu_write_hdr/gpu_submit()`: 底层virtqueue提交（双描述符 cmd+resp，spin-wait）
  - `gpu_create_resource/attach_backing/set_scanout/transfer/flush`: 完整2D命令链
  - `gpu_blit(x,y,w,h)` / `gpu_flip()`: 高层 dirty-region / 全屏刷新接口
  - `gpu_fb_base()`: 0xA00000 guest framebuffer; `gpu_ctx_create/submit_3d` virgl 3D命令
- **`ui_settings.hl`**: 新建设置中心窗口 (~270行)
  - Display / Audio / Network / About 四标签页
  - Audio: 音量进度条 + 键盘 +/- 调节 + Apply → `mixer_set_master_volume()`
  - Network: IP / MAC / 网关实时显示; About: 版本/架构/运行时间
- **`wm.hl`**: 键盘分发 + 新辅助函数
  - `wm_key_dispatch(key)`: 键盘事件路由到焦点模块
  - `wm_win_x/y/w/h()`, `wm_destroy_window()`: 新增窗口坐标/销毁辅助
  - `wm_draw_all()` / `wm_mouse_click()`: 集成 ui_files + ui_settings 渲染与点击
- **`shell.hl`**: 新增 `settings` 命令 → 73条命令



## Iteration 131 — IR→x86 Native Backend + Audio Fix + File Manager

- **`codegen.hl`**: 实现 `ir_emit_x86` — 将所有 37 条 IR 指令翻译为 x86_64 机器码
  - 新增辅助函数：`ir_cg_init / ir_cg_phys / ir_cg_load / ir_cg_load_into / ir_cg_store`
  - 新增标签/跳转回填：`ir_cg_define_label / ir_cg_add_patch / ir_cg_patch_labels`
  - `compile_native()` Phase 4 注释代码已激活，原生编译管线完整通路打通
- **`mixer.hl`**: 修复 `mixer_mix()` 关键 Bug
  - 新增 `mixer_clamp(v, lo, hi)` 辅助函数
  - 解注并修正变量定义（`sample / left_vol / right_vol / out_off / cur_l / cur_r`）
  - 用 `stream_done` 标志替换非法 `break` 语句
  - 将注释的 `ac97_submit_buffer` 替换为正确的 `ac97_play()` 调用
- **`linker.hl`**: 扩充 `linker_register_builtins()` 内置符号列表
  - 新增 38 个缺失符号（`clamp / mem_read_* / mem_write_* / port_in_* / port_out_* / serial_print` 等）
  - 解决剩余 1 个未解析重定位
- **`ui_files.hl`**: 新建 — 文件管理器窗口（228 行）
  - `uifiles_open / close / render / tick / navigate / handle_key`
  - 支持目录导航（Enter 进入，Backspace 返回，Escape 关闭）
  - 滚动条、选中高亮、状态栏（文件大小信息）
- **`shell.hl`**: 新增 3 条命令（总计 72 条）
  - `sysmon` → 打开系统监控窗口
  - `files` → 打开文件管理器
  - `audiotest` → 440 Hz 蜂鸣测试



- **`ui_sysmon.hl`**: 新建 — 系统监控窗口
  - 实时显示：运行时间、RTC 时钟、内存使用率（进度条）
  - 任务计数：Running / Ready / Blocked / Dead
  - 窗口状态：打开数 / 当前焦点
  - 每 2 秒自动刷新
- **`ui_notify.hl`**: 新建 — Toast 通知系统
  - 4 种类型：info / success / warning / error
  - 最多 4 条同时显示，屏幕右上角堆叠
  - 自动消失（TTL 3 秒）
  - FIFO 队列，满时循环替换最早一条
  - 左侧彩色强调条 + 边框 + 阴影
- **`wm.hl`**: 集成系统监控和通知渲染
- **`ui_desktop.hl`**: 监控器启动器现打开真实系统监控窗口
  - 桌面 tick 驱动监控器和通知计时器
- **`HicOS_UIServer.hl`**: IPC 消息处理完善
  - 新增 CREATE_WIN / DESTROY_WIN / SET_TITLE 消息处理
  - 合成后向焦点客户端发送 FOCUS_EVENT
  - 统计信息新增通知计数

## Iteration 129 — 窗口标题文字 + 图形安装器

- **`wm.hl`**: 窗口标题文字渲染
  - 新增 `wm_titles[]` 并行数组存储窗口标题字符串
  - `wm_get_title()` / `wm_set_title()`: 读写窗口标题
  - 标题栏现渲染窗口名称文字（自动截断防溢出）
  - 内容区点击路由到安装器模块
  - 安装器窗口内容渲染集成
- **`ui_installer.hl`**: 新建 — 图形安装器多步向导
  - 5 步驤：Welcome → Detect → Confirm → Install → Complete
  - 每步独立渲染：标签 / 分隔线 / 徽章 / 进度条 / 按钮
  - 磁盘检测：自动识别 ATA/AHCI/VirtIO 后端
  - 容量校验 + 危险警告
  - 实际磁盘写入 + MBR 修正 + 0x55AA 校验
  - 进度条实时显示安装状态
  - Back / Next / Install / Close 导航按钮
- **`ui_desktop.hl`**: 任务栏窗口按钮现显示窗口标题而非索引
  - Installer 启动器现打开图形安装器窗口
- **`build.hl`**: 新增 `ui_installer.hl` 到编译序列

## Iteration 128 — 桌面编排层 + 模态对话框 + UI Server 集成

- **`ui_desktop.hl`**: 新建 — 桌面编排层
  - 顶部栏：品牌文字 + RTC 实时时钟 + 窗口计数指示器
  - 底部 dock：应用启动器按钮（Terminal / Installer / Monitor）
  - dock 窗口按钮带编号标签
  - 应用启动器与窗口按钮间分隔线
  - `uidsk_launch_app()`: 点击 Terminal 启动图形终端
  - `uidsk_tick()`: 每秒更新时钟显示
  - 路由键盘/鼠标事件到对话框和启动器
- **`ui_dialog.hl`**: 新建 — 模态对话框系统
  - 4 种对话框：INFO / CONFIRM / WARNING / ERROR
  - 键盘导航：Tab 切换、Enter 确认、Esc 取消
  - 鼠标点击按钮
  - 半透明遮罩覆盖
  - 标题栏颜色按对话框类型变化（蓝/黄/红）
  - 便捷包装：`ui_dialog_info/confirm/warn/error()`
- **`wm.hl`**: 集成桌面层和对话框
  - `wm_draw_all()` 现委托 `uidsk_draw_chrome()` 绘制桌面
  - `wm_draw_all()` 渲染结束后绘制图形终端内容和对话框覆盖
  - `wm_mouse_click()` 优先路由对话框和桌面启动器
- **`HicOS_UIServer.hl`**: 集成桌面层
  - `uis_init()` 现调用 `uidsk_init()` 初始化桌面
  - `uis_tick()` 现调用 `uidsk_tick()` 更新时钟
  - `uis_dispatch_key()` 优先路由键盘事件到对话框
- **`build.hl`**: 新增 `ui_dialog.hl` 和 `ui_desktop.hl` 到编译序列

## Iteration 127 — UI 控件系统 + 任务栏 + 图形终端

- **`ui_controls.hl`**: 新建 — 基础控件系统
  - `ui_draw_char()` / `ui_draw_text()`: 8×16 位图字体文字绘制
  - `ui_label()` / `ui_label_colored()`: 静态文字标签
  - `ui_button()` / `ui_button_active()` / `ui_button_hit()`: 可点击矩形按钮
  - `ui_progress_bar()`: 水平进度条（百分比文字居中）
  - `ui_separator_h()` / `ui_separator_v()`: 水平/垂直分隔线
  - `ui_badge_ok()` / `ui_badge_warn()` / `ui_badge_err()`: 状态徽章
- **`ui_terminal.hl`**: 新建 — 图形终端窗口
  - 80×25 字符网格内嵌 wm 窗口
  - 64 行滚动缓冲区（cell buffer at 0x900000）
  - 逐行滚屏 + VGA 16 色 ARGB 调色板
  - 光标闪烁渲染
  - `uiterm_open()` / `uiterm_close()` / `uiterm_write()` / `uiterm_render()` 完整生命周期
- **`wm.hl`**: 任务栏与最小化
  - 新增最小化按钮（标题栏关闭按钮左侧）
  - `wm_minimize_window()` / `wm_restore_window()`
  - 底部 dock 任务栏绘制窗口按钮（聚焦高亮 / 普通灰色）
  - 任务栏点击：聚焦 / 最小化 / 恢复窗口
  - 顶部栏 "HicOS" 品牌文字绘制
- **`build.hl`**: 新增 `ui_controls.hl` 与 `ui_terminal.hl` 到编译序列

## Iteration 126 — 窗口交互基础完善

- **`wm.hl`**: 窗口管理器从静态绘制推进到可交互基础设施
  - 新增窗口 flags 辅助：可见 / 聚焦 / 最小化
  - 新增 `wm_focus_window()` 与 `wm_raise_window()`
  - 新增窗口、标题栏、关闭按钮命中测试
  - 鼠标点击现支持：聚焦、置顶、标题栏拖动、关闭窗口
  - 拖动过程加入屏幕边界和桌面顶栏/底栏约束
  - 修复主题接入后旧 `WM_TITLE_HEIGHT` 常量残留
  - `wm_create_window()` 现记录 `title_ptr` 并自动聚焦新窗口
- **`HicOS_WindowManager.hl`**: `hicos_wm_focus()` 改为直接调用 `wm_focus_window()`
- **`HicOS_UIServer.hl`**: 创建窗口时向 `wm_create_window()` 透传 owner PID

## Iteration 125 — UI 主题基线 + 窗口管理器接入

- **`ui_theme.hl`**: 新建 — HicOS UI 主题模块
  - 统一桌面、面板、边框、标题栏、阴影、成功/警告/错误色
  - 统一标题栏高度、顶栏高度、底栏高度、阴影偏移等基础度量
- **`wm.hl`**: 接入统一主题
  - 桌面背景改为从 `ui_theme` 读取
  - 新增桌面顶部栏/底部栏基础 chrome
  - 窗口接入统一边框/标题栏/阴影/内容区颜色
  - 关闭按钮颜色接入主题错误色
- **`build.hl`**: 新增 `ui_theme.hl` 到图形/UI 模块编译序列

## Iteration 124 — 完整当前镜像裸机安装

- **`self_image.hl`**: 自映像写盘路径从“回读目标盘”升级为“从内存重建完整启动镜像”
  - `self_image_read_sector(lba, buf_addr)`: 按 LBA 重建当前运行镜像
    - `LBA0` → `0x7C00` stage1/MBR
    - `LBA1` → `0x8000` stage2
    - `LBA2+` → `0x100000` kernel payload
  - `self_install_to_disk()`: 逐扇区将当前启动镜像直接写入目标磁盘
  - 默认镜像元数据同步到最新构建：`161280` bytes / `315` sectors
- **`installer.hl`**: 安装器主流程升级为真实裸机安装闭环
  - `[3/7]` 检查当前运行镜像
  - `[4/7]` 校验目标磁盘容量是否足够容纳完整镜像
  - `[5/7]` 执行 raw boot image 全盘写入
  - `[6/7]` Legacy BIOS 路径补写/修正 MBR 分区元数据
  - `[7/7]` 回读校验 `0x55AA` 启动签名
  - 移除文件加载时自动执行 `installer_main()` 的危险行为
- **`kernel_entry.hl`**: 原生 `install` 命令改为直接委托 `installer_main()`
  - 不再使用旧的 VirtIO-only 假安装流程
  - 现在走 ATA PIO / AHCI / VirtIO 三后端统一安装器
- **`manifest.hl`**: `BOOT_IMAGE_BYTES` 同步为 `161280`





