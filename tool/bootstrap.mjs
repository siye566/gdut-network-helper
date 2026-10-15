#!/usr/bin/env node
// Generate in a disposable directory. Only newly added platform directories are configured.
import { constants } from 'node:fs';
import { access, cp, mkdir, mkdtemp, readFile, readdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const platforms = ['windows', 'macos', 'android', 'ios'];
const exists = async (name) => access(name).then(() => true, () => false);
const read = (name) => readFile(name, 'utf8');
const write = async (name, content) => {
  await mkdir(path.dirname(name), { recursive: true });
  await writeFile(name, content, 'utf8');
};

function olderThan(version, minimum) {
  const actual = version.split('.').map(Number);
  const required = minimum.split('.').map(Number);
  for (let i = 0; i < required.length; i++) {
    if ((actual[i] ?? 0) !== required[i]) return (actual[i] ?? 0) < required[i];
  }
  return false;
}

function plistEntry(source, key, xml) {
  if (source.includes(`<key>${key}</key>`)) throw new Error(`Unexpected existing plist key: ${key}`);
  const end = source.lastIndexOf('</dict>');
  if (end < 0) throw new Error('Unexpected plist template');
  return `${source.slice(0, end)}\t<key>${key}</key>\n\t${xml}\n${source.slice(end)}`;
}

async function configureAndroid(base) {
  const manifest = path.join(base, 'app/src/main/AndroidManifest.xml');
  let xml = await read(manifest);
  for (const permission of ['INTERNET', 'ACCESS_NETWORK_STATE']) {
    if (!xml.includes(`android.permission.${permission}`)) {
      xml = xml.replace(/(<manifest\b[^>]*>)/, `$1\n    <uses-permission android:name="android.permission.${permission}" />`);
    }
  }
  xml = xml.replace(/<application\b/, '<application\n        android:allowBackup="false"\n        android:networkSecurityConfig="@xml/network_security_config"');
  await write(manifest, xml);
  for (const name of ['MainActivity.kt', 'network_security_config.xml']) {
    const destination = name.endsWith('.kt')
      ? 'app/src/main/kotlin/cn/gduthelper/gdut_network_helper/MainActivity.kt'
      : 'app/src/main/res/xml/network_security_config.xml';
    await write(path.join(base, destination), await read(path.join(root, 'platform_templates/android', name)));
  }
  const gradle = path.join(base, 'app', await exists(path.join(base, 'app/build.gradle.kts')) ? 'build.gradle.kts' : 'build.gradle');
  let build = await read(gradle);
  const expression = path.extname(gradle) === '.kts'
    ? /\bminSdk\s*=\s*[^\r\n]+/
    : /\bminSdkVersion\s+[^\r\n]+/;
  if (!expression.test(build)) throw new Error('Cannot locate Android minSdk in generated Gradle file');
  build = build.replace(expression, path.extname(gradle) === '.kts'
    ? 'minSdk = maxOf(24, flutter.minSdkVersion)'
    : 'minSdkVersion Math.max(24, flutter.minSdkVersion)');
  await write(gradle, build);
  // connectivity_plus 7.3.2 requires AGP >=8.12.1 and Gradle >=8.13.
  const settings = path.join(base, await exists(path.join(base, 'settings.gradle.kts'))
    ? 'settings.gradle.kts' : 'settings.gradle');
  let plugins = await read(settings);
  const agp = /(id\s*(?:\(\s*)?["']com\.android\.application["']\s*\)?\s+version\s+["'])(\d+\.\d+(?:\.\d+)?)(["'])/;
  const agpMatch = plugins.match(agp);
  if (!agpMatch) throw new Error('Cannot locate Android Gradle plugin version in generated project');
  if (olderThan(agpMatch[2], '8.12.1')) {
    plugins = plugins.replace(agp, (_, prefix, version, quote) => `${prefix}8.12.1${quote}`);
    await write(settings, plugins);
  }
  const wrapper = path.join(base, 'gradle/wrapper/gradle-wrapper.properties');
  let properties = await read(wrapper);
  const distribution = /gradle-(\d+\.\d+(?:\.\d+)?)-(all|bin)\.zip/;
  const gradleMatch = properties.match(distribution);
  if (!gradleMatch) throw new Error('Cannot locate generated Gradle distribution');
  if (olderThan(gradleMatch[1], '8.13')) {
    properties = properties.replace(distribution, `gradle-8.13-${gradleMatch[2]}.zip`);
    await write(wrapper, properties);
  }
}

// Generated Apple projects may include template test targets even with --empty.
// Remove those generated references before copying; no existing user project is touched.
function stripGeneratedTestTargets(source) {
  const objectPattern = /^\t\t([A-F0-9]{24})(?: \/\* (.*?) \*\/)? = \{(?:[^\r\n]*\};|\r?\n[\s\S]*?^\t\t\};)/gm;
  const objects = [...source.matchAll(objectPattern)].map((match) => ({
    id: match[1], label: match[2] ?? '', text: match[0]
  }));
  const removed = new Set(objects.filter((object) => /RunnerTests/.test(object.label) || /productType = "com.apple.product-type.bundle.unit-test"/.test(object.text)).map((object) => object.id));
  let changed = true;
  while (changed) {
    changed = false;
    for (const object of objects.filter((item) => removed.has(item.id))) {
      const owned = [...object.text.matchAll(/(?:buildConfigurationList|productReference|fileRef|targetProxy) = ([A-F0-9]{24})/g)].map((match) => match[1]);
      for (const match of object.text.matchAll(/(?:buildPhases|buildConfigurations|dependencies|children|files) = \(([\s\S]*?)\);/g)) {
        owned.push(...(match[1].match(/[A-F0-9]{24}/g) ?? []));
      }
      for (const id of owned) {
        if (!removed.has(id)) { removed.add(id); changed = true; }
      }
    }
  }
  for (const object of objects) if (removed.has(object.id)) source = source.replace(object.text, '');
  for (const id of removed) {
    source = source.replace(new RegExp(`^\\s*${id} = \\{[\\s\\S]*?^\\s*\\};\\n`, 'gm'), '');
    source = source.replace(new RegExp(`^.*\\b${id}\\b.*(?:\\r?\\n|$)`, 'gm'), '');
  }
  return { source, removed };
}

async function configureApple(base, platform) {
  const info = path.join(base, 'Runner/Info.plist');
  let plist = await read(info);
  plist = plistEntry(plist, 'NSLocalNetworkUsageDescription', '<string>连接校园认证服务器，帮助你完成校园网登录。</string>');
  // ATS domain exceptions cannot name a numeric IP. Dart native IO performs the
  // actual portal request and enforces an exact IP/port allowlist in application code.
  await write(info, plist);
  const entitlementFiles = ['DebugProfile.entitlements', 'Release.entitlements'];
  for (const name of entitlementFiles) {
    const filename = path.join(base, 'Runner', name);
    let entitlement = await exists(filename) ? await read(filename)
      : '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n</dict>\n</plist>\n';
    if (!entitlement.includes('<key>keychain-access-groups</key>')) entitlement = plistEntry(entitlement, 'keychain-access-groups', '<array/>');
    if (platform === 'macos' && !entitlement.includes('<key>com.apple.security.network.client</key>')) {
      entitlement = plistEntry(entitlement, 'com.apple.security.network.client', '<true/>');
    }
    await write(filename, entitlement);
  }
  const project = path.join(base, 'Runner.xcodeproj/project.pbxproj');
  const stripped = stripGeneratedTestTargets(await read(project));
  let pbx = stripped.source;
  if (platform === 'ios') {
    let configured = 0;
    pbx = pbx.replace(/(^\t\t[A-F0-9]{24} \/\* (Debug|Profile|Release) \*\/ = \{[\s\S]*?^\t\t\};)/gm, (block, _, configuration) => {
      if (!/INFOPLIST_FILE = Runner\/Info.plist;/.test(block)) return block;
      const entitlements = configuration === 'Release' ? 'Release.entitlements' : 'DebugProfile.entitlements';
      configured++;
      if (/CODE_SIGN_ENTITLEMENTS\s*=/.test(block)) {
        return block.replace(/CODE_SIGN_ENTITLEMENTS\s*=\s*[^;]+;/, `CODE_SIGN_ENTITLEMENTS = Runner/${entitlements};`);
      }
      return block.replace(/buildSettings = \{/, `buildSettings = {\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/${entitlements};`);
    });
    if (configured !== 3) throw new Error(`Expected three iOS Runner signing configurations, found ${configured}`);
  }
  await write(project, pbx);
  const schemes = path.join(base, 'Runner.xcodeproj/xcshareddata/xcschemes');
  if (await exists(schemes)) {
    for (const name of await readdir(schemes)) {
      if (!name.endsWith('.xcscheme')) continue;
      const file = path.join(schemes, name);
      let scheme = await read(file);
      scheme = scheme.replace(/<TestableReference\b[\s\S]*?<\/TestableReference>/g, (block) =>
        [...stripped.removed].some((id) => block.includes(id)) ? '' : block);
      await write(file, scheme);
    }
  }
}

async function main() {
  const missing = [];
  for (const platform of platforms) {
    if (await exists(path.join(root, platform))) console.log(`Skip existing ${platform}/; its runner and configuration are preserved.`);
    else missing.push(platform);
  }
  if (!missing.length) { console.log('No missing platform directories. Nothing changed.'); return; }
  const temporary = await mkdtemp(path.join(tmpdir(), 'gdut-helper-bootstrap-'));
  const generated = path.join(temporary, 'gdut_network_helper');
  const flutter = process.platform === 'win32' ? 'flutter.bat' : 'flutter';
  // Keep shell arguments fixed; pass a temporary path containing spaces via cwd.
  const result = spawnSync(flutter, ['create', '--platforms=windows,macos,android,ios', '--empty', '--no-pub', '--project-name', 'gdut_network_helper', '--org', 'cn.gduthelper', 'gdut_network_helper'], {
    cwd: temporary, stdio: 'inherit', shell: process.platform === 'win32'
  });
  if (result.error || result.status !== 0) throw new Error('Flutter shell generation failed. Install Flutter and put flutter on PATH first.');
  for (const platform of missing) {
    const source = path.join(generated, platform);
    if (!await exists(source)) throw new Error(`Flutter did not generate ${platform}/`);
    if (platform === 'android') await configureAndroid(source);
    if (platform === 'ios' || platform === 'macos') await configureApple(source, platform);
  }
  for (const platform of missing) {
    const destination = path.join(root, platform);
    // Refuse to merge if a directory appeared while Flutter was generating its shells.
    if (await exists(destination)) throw new Error(`${platform}/ appeared during generation; refusing to overwrite it.`);
    await cp(path.join(generated, platform), destination, {
      recursive: true, force: false, errorOnExist: true, mode: constants.COPYFILE_EXCL,
      filter: (source) => !/(?:^|[\\/])(?:test|tests|RunnerTests|integration_test)(?:[\\/]|$)/i.test(source)
    });
    console.log(`Added and configured ${platform}/`);
  }
  console.log('Existing pubspec.yaml, lib/ and platform runners were not modified.');
  console.log('Next: flutter pub get; then run/build on a supported host. No compilation has been performed.');
  console.log(`Generated scratch shell retained at: ${temporary}`);
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
