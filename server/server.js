/**
 * 历史定位记录 API 服务
 *
 * 提供共享历史定位记录的增删查接口, 所有设备访问同一份数据.
 * 数据以 JSON 文件存储, 服务器重启后不丢失.
 *
 * 接口:
 *   GET    /api/location-history        获取历史列表 (createdAt DESC)
 *   POST   /api/location-history        新增/更新历史 (name+lat+lng 相同则更新 createdAt)
 *   DELETE /api/location-history/:id     删除指定历史
 *
 * 自动清理: 每次请求都会清理 createdAt 超过 5 天的记录.
 *
 * 启动: node server.js
 * 默认端口: 3000 (可通过 PORT 环境变量修改)
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = path.join(DATA_DIR, 'location-history.json');
const MAX_AGE_DAYS = 5;
const MAX_AGE_MS = MAX_AGE_DAYS * 24 * 60 * 60 * 1000;

// 确保数据文件存在
function ensureDataFile() {
    if (!fs.existsSync(DATA_DIR)) {
        fs.mkdirSync(DATA_DIR, { recursive: true });
    }
    if (!fs.existsSync(DATA_FILE)) {
        fs.writeFileSync(DATA_FILE, JSON.stringify([], null, 2));
    }
}

// 读取全部记录
function readRecords() {
    ensureDataFile();
    try {
        const raw = fs.readFileSync(DATA_FILE, 'utf-8');
        const arr = JSON.parse(raw);
        return Array.isArray(arr) ? arr : [];
    } catch (e) {
        return [];
    }
}

// 写入记录
function writeRecords(records) {
    ensureDataFile();
    fs.writeFileSync(DATA_FILE, JSON.stringify(records, null, 2));
}

// 清理超过 5 天的记录
function cleanupOldRecords(records) {
    const now = Date.now();
    return records.filter(r => {
        const created = new Date(r.createdAt).getTime();
        return (now - created) < MAX_AGE_MS;
    });
}

// 生成下一个自增 id
function nextId(records) {
    if (records.length === 0) return 1;
    return Math.max(...records.map(r => Number(r.id) || 0)) + 1;
}

// 发送 JSON 响应 (带 CORS 头, 允许 App 跨域访问)
function sendJSON(res, status, body) {
    const json = JSON.stringify(body);
    res.writeHead(status, {
        'Content-Type': 'application/json; charset=utf-8',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    });
    res.end(json);
}

// 读取请求 body 并解析 JSON
function readBody(req) {
    return new Promise((resolve, reject) => {
        let data = '';
        req.on('data', chunk => { data += chunk; });
        req.on('end', () => {
            try {
                resolve(data ? JSON.parse(data) : {});
            } catch (e) {
                resolve({});
            }
        });
        req.on('error', reject);
    });
}

const server = http.createServer(async (req, res) => {
    // CORS 预检
    if (req.method === 'OPTIONS') {
        sendJSON(res, 204, {});
        return;
    }

    const url = new URL(req.url, `http://localhost:${PORT}`);
    const pathname = url.pathname;

    // GET /api/location-history —— 获取历史列表
    if (req.method === 'GET' && pathname === '/api/location-history') {
        let records = readRecords();
        records = cleanupOldRecords(records);
        // 按 createdAt 倒序 (最新在最上面)
        records.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
        writeRecords(records); // 持久化清理结果
        sendJSON(res, 200, { success: true, data: records });
        return;
    }

    // POST /api/location-history —— 新增/更新历史
    if (req.method === 'POST' && pathname === '/api/location-history') {
        const body = await readBody(req);
        const name = String(body.name || '').trim();
        const latitude = Number(body.latitude);
        const longitude = Number(body.longitude);
        if (!name || !isFinite(latitude) || !isFinite(longitude)) {
            sendJSON(res, 400, { success: false, error: '参数错误: 需要 name, latitude, longitude' });
            return;
        }
        let records = readRecords();
        records = cleanupOldRecords(records);
        // 去重: name + latitude + longitude 相同则只更新 createdAt (变成最近使用)
        const roundedLat = latitude.toFixed(6);
        const roundedLng = longitude.toFixed(6);
        const existingIdx = records.findIndex(r =>
            r.name === name &&
            Number(r.latitude).toFixed(6) === roundedLat &&
            Number(r.longitude).toFixed(6) === roundedLng
        );
        const now = new Date().toISOString();
        if (existingIdx >= 0) {
            // 已存在相同定位: 更新时间, 不产生重复数据
            records[existingIdx].createdAt = now;
            writeRecords(records);
            sendJSON(res, 200, { success: true, data: records[existingIdx] });
            return;
        }
        const newRecord = {
            id: nextId(records),
            name,
            latitude,
            longitude,
            createdAt: now
        };
        records.push(newRecord);
        writeRecords(records);
        sendJSON(res, 200, { success: true, data: newRecord });
        return;
    }

    // DELETE /api/location-history/:id —— 删除指定历史
    if (req.method === 'DELETE' && pathname.startsWith('/api/location-history/')) {
        const idStr = pathname.split('/').pop();
        const id = Number(idStr);
        if (!isFinite(id) || isNaN(id)) {
            sendJSON(res, 400, { success: false, error: '无效的 id' });
            return;
        }
        let records = readRecords();
        records = cleanupOldRecords(records);
        const before = records.length;
        records = records.filter(r => Number(r.id) !== id);
        writeRecords(records);
        const deleted = records.length < before;
        sendJSON(res, 200, { success: true, data: { id, deleted } });
        return;
    }

    sendJSON(res, 404, { success: false, error: 'Not Found' });
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`历史定位 API 服务已启动: http://0.0.0.0:${PORT}`);
    console.log(`数据文件: ${DATA_FILE}`);
});
