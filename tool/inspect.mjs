#!/usr/bin/env node
// Read-only field diagnosis. Never calls login, logout, perceive or operator APIs.
const origin = 'http://10.0.3.2';
const limit = 512 * 1024;

async function read(path) {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 10000);
  try {
    const response = await fetch(`${origin}${path}`, {
      redirect: 'manual', signal: abort.signal,
      headers: { 'Cache-Control': 'no-store' },
    });
    if (response.status !== 200) throw new Error('校园认证入口未返回正常响应。');
    let size = 0;
    const chunks = [];
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > limit) { abort.abort(); throw new Error('认证响应超出预期大小。'); }
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8');
  } finally { clearTimeout(timer); }
}

function parseJsonp(text) {
  const value = text.trim();
  const match = /^(?:dr1003|drdiagnose)\s*\(\s*([\s\S]*)\s*\)\s*;?$/.exec(value);
  return JSON.parse(match ? match[1] : value);
}

try {
  const page = await read('/a79.htm');
  const recognized = /Dr\.COMWebLoginID_0\.htm/.test(page)
    && /v4serip\s*=\s*['"]10\.0\.3\.2['"]/.test(page);
  if (!recognized) throw new Error('当前页面与已核实的大学城认证门户不一致，请使用浏览器确认。');
  const status = parseJsonp(await read(`/drcom/chkstatus?callback=drdiagnose&v=${Date.now()}`));
  const flag = Number(status.result);
  console.log(JSON.stringify({
    portal: 'GDUT 大学城 Dr.COM',
    reachable: true,
    authentication: flag === 1 ? '认证在线' : flag === 0 ? '需要认证' : '状态未知，请打开网页登录',
    dynamicIpAvailable: /v46ip\s*=\s*['"]\s*\d+\.\d+\.\d+\.\d+\s*['"]/.test(page),
    readOnly: true,
  }, null, 2));
} catch (_) {
  console.error('检查未完成：请连接大学城校园 Wi-Fi，关闭影响校内路由的代理后重试，或打开 http://10.0.3.2/a79.htm 确认。未提交任何账号密码。');
  process.exitCode = 1;
}
