package com.psyche.kelivo.workspace

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RootfsNodeDnsTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun shim(rootfs: File) = File(rootfs, RootfsNodeDns.GUEST_PATH.removePrefix("/"))

    private fun nodeOptions(argv: List<String>): String? =
        argv.firstOrNull { it.startsWith("NODE_OPTIONS=") }?.removePrefix("NODE_OPTIONS=")

    @Test
    fun anUnchangedShimIsNotRewrittenAndAnOutdatedOneIsReplaced() {
        val rootfs = tmp.newFolder()
        RootfsNodeDns.ensureInstalled(rootfs)
        val file = shim(rootfs)
        assertEquals(RootfsNodeDns.SCRIPT, file.readText())
        file.setLastModified(1_000L)
        RootfsNodeDns.ensureInstalled(rootfs)
        assertEquals(1_000L, file.lastModified())
        file.writeText("old")
        RootfsNodeDns.ensureInstalled(rootfs)
        assertEquals(RootfsNodeDns.SCRIPT, file.readText())
        assertEquals(listOf("node-dns.cjs"), file.parentFile!!.list()!!.toList())
    }

    @Test
    fun guestAbsoluteLinksResolveInsideTheRootfs() {
        val rootfs = tmp.newFolder()
        File(rootfs, "usr/etc").mkdirs()
        Files.createSymbolicLink(File(rootfs, "etc").toPath(), File("/usr/etc").toPath())
        RootfsNodeDns.ensureInstalled(rootfs)
        assertTrue(File(rootfs, "usr/etc/moru/node-dns.cjs").isFile)
        assertTrue(RootfsNodeDns.isInstalled(rootfs))
    }

    @Test
    fun nodeOptionsLoadTheShimFirstAndOnce() {
        val own = "--require=" + RootfsNodeDns.GUEST_PATH
        assertEquals(own, RootfsNodeDns.nodeOptions(null))
        assertEquals(own, RootfsNodeDns.nodeOptions("  "))
        assertEquals("$own --max-old-space-size=512", RootfsNodeDns.nodeOptions("--max-old-space-size=512"))
        assertEquals("--max-old-space-size=512 $own", RootfsNodeDns.nodeOptions("--max-old-space-size=512 $own"))
    }

    @Test
    fun guestCommandsLoadTheShimOnlyWhenItIsInstalled() {
        val rootfs = tmp.newFolder()
        val agent = "--require=/root/.config/moru-agents/fs-compat.cjs"
        fun argv(env: Map<String, String>, command: String?) =
            ProotCommand.guestCommand(rootfs, "/", command, env, "/bin/sh")
        assertEquals(null, nodeOptions(argv(mapOf("HOME" to "/root"), "node -v")))
        assertEquals(agent, nodeOptions(argv(mapOf("NODE_OPTIONS" to agent), "node -v")))

        RootfsNodeDns.ensureInstalled(rootfs)
        val own = "--require=" + RootfsNodeDns.GUEST_PATH
        assertEquals(own, nodeOptions(argv(mapOf("HOME" to "/root"), "node -v")))
        assertEquals(own, nodeOptions(argv(mapOf("HOME" to "/root"), null)))
        val merged = argv(mapOf("NODE_OPTIONS" to agent), "node -v")
        assertEquals("$own $agent", nodeOptions(merged))
        assertEquals(1, merged.count { it.startsWith("NODE_OPTIONS=") })

        val chroot = ChrootCommand.build(
            nativeLibDir = File("/nativelib"),
            rootfsDir = rootfs,
            binds = emptyList(),
            cwd = "/workspace",
            command = "node -v",
            env = linkedMapOf("NODE_OPTIONS" to agent),
            shell = "/bin/sh",
            tag = "run-1",
            uid = 10538,
            gid = 10538,
            appDataDir = File("/data/app"),
            suPath = "/system/bin/su",
        )
        assertTrue(chroot.argv.last().contains("'NODE_OPTIONS=$own $agent'"))

        shim(rootfs).delete()
        assertFalse(RootfsNodeDns.isInstalled(rootfs))
        assertEquals(null, nodeOptions(argv(mapOf("HOME" to "/root"), "node -v")))
    }

    @Test
    fun anUnansweredAaaaQueryFallsBackToIpv4() {
        val node = ProcessBuilder("/bin/sh", "-c", "command -v node").start()
        assumeTrue(node.waitFor() == 0)
        val dir = tmp.newFolder()
        val shim = File(dir, "node-dns.cjs").apply { writeText(RootfsNodeDns.SCRIPT) }
        val stub = File(dir, "musl-stub.cjs").apply { writeText(MUSL_STUB) }
        val scenario = File(dir, "scenario.cjs").apply { writeText(SCENARIO) }
        fun run(vararg preload: File): Pair<Int, String> {
            val process = ProcessBuilder(
                listOf("node") + preload.map { "--require=" + it.absolutePath } + scenario.absolutePath,
            ).redirectErrorStream(true).start()
            assertTrue(process.waitFor(60, TimeUnit.SECONDS))
            return process.exitValue() to process.inputStream.bufferedReader().readText()
        }
        val (code, output) = run(stub, shim)
        assertEquals(output, 0, code)
        assertEquals(
            listOf(
                "dual [\"::1\",6]",
                "dual all [[{\"address\":\"::1\",\"family\":6},{\"address\":\"127.0.0.1\",\"family\":4}],null]",
                "missing error ENOTFOUND calls missing.moru.test/0",
                "literal [\"127.0.0.1\",4]",
                "broken [\"127.0.0.1\",4]",
                "broken again [\"127.0.0.1\",4] unspec calls +0",
                "broken all [[{\"address\":\"127.0.0.1\",\"family\":4}],null]",
                "broken promises {\"address\":\"127.0.0.1\",\"family\":4}",
                "broken promisify {\"address\":\"127.0.0.1\",\"family\":4}",
                "v6only [\"::1\",6]",
                "family4 kept [\"127.0.0.1\",4]",
                "after window [\"127.0.0.1\",4] unspec calls +1",
                "http served",
                "fetch served",
            ),
            output.trim().lines(),
        )
        // Without the shim the same lookups fail the way they do on the phone.
        val (failed, error) = run(stub)
        assertTrue(failed != 0 && error.contains("EAI_AGAIN"))
    }

    private companion object {
        // Models musl: a lookup without a family fails with EAI_AGAIN when the
        // AAAA query goes unanswered, although the A answer exists.
        val MUSL_STUB = """
            'use strict';
            // Models musl: a lookup without a family fails with EAI_AGAIN when the AAAA
            // query goes unanswered, although the A answer exists.
            const dns = require('node:dns');
            const calls = (globalThis.moruDnsCalls = []);
            const table = {
              'broken.moru.test': { 0: 'EAI_AGAIN', 4: ['127.0.0.1'], 6: 'ENOTFOUND' },
              'v6only.moru.test': { 0: 'EAI_AGAIN', 4: 'ENOTFOUND', 6: ['::1'] },
              'missing.moru.test': { 0: 'ENOTFOUND', 4: 'ENOTFOUND', 6: 'ENOTFOUND' },
              'dual.moru.test': { 0: ['::1', '127.0.0.1'], 4: ['127.0.0.1'], 6: ['::1'] },
            };
            function family(options) {
              if (typeof options === 'number') return options;
              return (options && options.family) || 0;
            }
            function answer(host, options) {
              const f = family(options);
              calls.push(host + '/' + f);
              const result = table[host][f];
              if (typeof result === 'string') {
                return { error: Object.assign(new Error('getaddrinfo ' + result + ' ' + host), {
                  code: result, syscall: 'getaddrinfo', hostname: host }) };
              }
              const list = result.map((address) => ({ address, family: address.includes(':') ? 6 : 4 }));
              return { list };
            }
            const realLookup = dns.lookup;
            dns.lookup = function (host, options, callback) {
              if (typeof options === 'function') { callback = options; options = undefined; }
              if (!table[host]) return realLookup.apply(this, arguments);
              const { error, list } = answer(host, options);
              setTimeout(() => {
                if (error) return callback(error);
                if (options && options.all) return callback(null, list);
                callback(null, list[0].address, list[0].family);
              }, 5);
              return {};
            };
            const realAsync = dns.promises.lookup;
            dns.promises.lookup = async function (host, options) {
              if (!table[host]) return realAsync.apply(this, arguments);
              const { error, list } = answer(host, options);
              await new Promise((resolve) => setTimeout(resolve, 5));
              if (error) throw error;
              return options && options.all ? list : list[0];
            };
        """.trimIndent() + "\n"

        val SCENARIO = """
            const dns = require('node:dns');
            const util = require('node:util');
            const http = require('node:http');
            const calls = globalThis.moruDnsCalls;
            const count = (name) => calls.filter((c) => c === name).length;
            const cb = (host, options) => new Promise((resolve) => {
              const done = (error, address, family) =>
                resolve(error ? 'error ' + error.code : JSON.stringify([address, family]));
              options === undefined ? dns.lookup(host, done) : dns.lookup(host, options, done);
            });
            (async () => {
              const out = [];
              out.push('dual ' + (await cb('dual.moru.test')));
              out.push('dual all ' + (await cb('dual.moru.test', { all: true })));
              out.push('missing ' + (await cb('missing.moru.test')) + ' calls ' + calls.filter((c) => c.startsWith('missing')).join(','));
              out.push('literal ' + (await cb('127.0.0.1')));
              out.push('broken ' + (await cb('broken.moru.test')));
              const before = count('broken.moru.test/0');
              out.push('broken again ' + (await cb('broken.moru.test', 0)) + ' unspec calls +' + (count('broken.moru.test/0') - before));
              out.push('broken all ' + (await cb('broken.moru.test', { all: true })));
              out.push('broken promises ' + JSON.stringify(await dns.promises.lookup('broken.moru.test')));
              out.push('broken promisify ' + JSON.stringify(await util.promisify(dns.lookup)('broken.moru.test')));
              out.push('v6only ' + (await cb('v6only.moru.test')));
              out.push('family4 kept ' + (await cb('dual.moru.test', { family: 4 })));
              const now = Date.now;
              Date.now = () => now() + 6 * 60 * 1000;
              const unspec = count('broken.moru.test/0');
              out.push('after window ' + (await cb('broken.moru.test')) + ' unspec calls +' + (count('broken.moru.test/0') - unspec));
              Date.now = now;
              await new Promise((resolve) => {
                const server = http.createServer((q, r) => r.end('served')).listen(0, '127.0.0.1', () => {
                  const port = server.address().port;
                  http.get('http://broken.moru.test:' + port, (r) => {
                    let body = '';
                    r.on('data', (d) => (body += d));
                    r.on('end', async () => {
                      out.push('http ' + body);
                      try {
                        out.push('fetch ' + (await (await fetch('http://broken.moru.test:' + port)).text()));
                      } catch (e) { out.push('fetch error ' + (e.cause && e.cause.code)); }
                      server.close(resolve);
                    });
                  }).on('error', (e) => { out.push('http error ' + e.code); server.close(resolve); });
                });
              });
              console.log(out.join('\n'));
            })();
        """.trimIndent() + "\n"
    }
}
