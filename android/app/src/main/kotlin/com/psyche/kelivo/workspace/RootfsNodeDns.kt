package com.psyche.kelivo.workspace

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * A Node.js preload that every guest process receives through NODE_OPTIONS
 * ([ProotCommand.guestCommand]), so agents, MCP servers, mini-app servers, npm
 * and Node started in the terminal all resolve names the same way.
 *
 * musl (Alpine) fails a whole getaddrinfo without an address family with
 * EAI_AGAIN when only the AAAA answer is missing or SERVFAIL, although the A
 * answer arrived (name_from_dns in src/network/lookup_name.c). glibc returns
 * the A answer. Some home routers answer AAAA queries that way, and Node asks
 * without a family by default, so every agent lost the network there. The
 * shim retries such a lookup with IPv4, then IPv6, and asks IPv4 first for a
 * few minutes after a rescue. Successful lookups and other errors are left
 * alone, so working IPv6 keeps being used.
 */
object RootfsNodeDns {
    const val GUEST_PATH = "/etc/moru/node-dns.cjs"

    val SCRIPT = """
        'use strict';
        // Written by Moru. musl's getaddrinfo fails a whole lookup without an address
        // family with EAI_AGAIN when only the AAAA query goes unanswered, although the
        // A answer arrived (some home routers). Node asks without a family by default,
        // so every Node program lost the network there. Such a lookup is retried with
        // IPv4, then IPv6; after a rescue IPv4 is asked first for a while. Successful
        // lookups and every other error stay untouched, so working IPv6 is still used.
        try {
          (function () {
            var dns = require('dns');
            var net = require('net');
            var util = require('util');
            var marker = Symbol.for('moru.dnsFallback');
            if (dns.lookup[marker]) return;
            var preferIpv4For = 5 * 60 * 1000;
            var preferIpv4Until = 0;

            function familyFree(hostname, options) {
              if (typeof hostname !== 'string' || hostname === '' || net.isIP(hostname)) {
                return false;
              }
              if (typeof options === 'number') return options === 0;
              if (options === undefined || options === null) return true;
              if (typeof options !== 'object') return false;
              return options.family === undefined || options.family === null ||
                options.family === 0;
            }

            function withFamily(options, family) {
              var copy = {};
              if (options && typeof options === 'object') {
                for (var key in options) {
                  if (Object.prototype.hasOwnProperty.call(options, key)) copy[key] = options[key];
                }
              }
              copy.family = family;
              return copy;
            }

            function rescued() {
              preferIpv4Until = Date.now() + preferIpv4For;
            }

            var lookup = dns.lookup;
            function moruLookup(hostname, options, callback) {
              if (typeof options === 'function') {
                callback = options;
                options = undefined;
              }
              if (typeof callback !== 'function' || !familyFree(hostname, options)) {
                return lookup.apply(this, arguments);
              }
              var self = this;
              var ipv4 = withFamily(options, 4);
              var ipv6 = withFamily(options, 6);
              function byFamily(error, done) {
                return lookup.call(self, hostname, ipv4, function (error4) {
                  if (!error4) return done(arguments);
                  lookup.call(self, hostname, ipv6, function (error6) {
                    if (!error6) return done(arguments);
                    callback(error || error4);
                  });
                });
              }
              if (Date.now() < preferIpv4Until) {
                return byFamily(null, function (result) {
                  callback.apply(null, result);
                });
              }
              return lookup.call(this, hostname, options, function (error) {
                if (!error || error.code !== 'EAI_AGAIN') return callback.apply(null, arguments);
                byFamily(error, function (result) {
                  rescued();
                  callback.apply(null, result);
                });
              });
            }
            moruLookup[marker] = true;
            moruLookup[util.promisify.custom] = function (hostname, options) {
              return new Promise(function (resolve, reject) {
                moruLookup(hostname, options, function (error, address, family) {
                  if (error) reject(error);
                  else resolve({ address: address, family: family });
                });
              });
            };
            dns.lookup = moruLookup;

            // dns.promises is experimental, and warns on every start, before Node 11.
            if (parseInt(process.versions.node, 10) < 11) return;
            var promises = dns.promises;
            if (!promises || typeof promises.lookup !== 'function') return;
            var lookupAsync = promises.lookup;
            promises.lookup = function (hostname, options) {
              if (!familyFree(hostname, options)) return lookupAsync.apply(this, arguments);
              var self = this;
              var ipv4 = withFamily(options, 4);
              var ipv6 = withFamily(options, 6);
              function byFamily(error) {
                return lookupAsync.call(self, hostname, ipv4).catch(function (error4) {
                  return lookupAsync.call(self, hostname, ipv6).catch(function () {
                    throw error || error4;
                  });
                });
              }
              if (Date.now() < preferIpv4Until) return byFamily(null);
              return lookupAsync.call(this, hostname, options).catch(function (error) {
                if (!error || error.code !== 'EAI_AGAIN') throw error;
                return byFamily(error).then(function (result) {
                  rescued();
                  return result;
                });
              });
            };
          })();
        } catch (error) {
          // Never stop a Node program from starting because of this compatibility shim.
        }
    """.trimIndent() + "\n"

    /** Best effort, like [RootfsProfile]: a rootfs the app cannot write keeps working. */
    @Synchronized
    fun ensureInstalled(rootfsDir: File) {
        try {
            val file = RootfsInfo.guestFile(rootfsDir, GUEST_PATH)
            if (file.isFile && file.readText() == SCRIPT) return
            val parent = file.parentFile ?: return
            parent.mkdirs()
            // A Node process may start while the shim is replaced: never let it
            // read a half-written file.
            val temporary = Files.createTempFile(parent.toPath(), ".node-dns-", ".tmp")
            try {
                temporary.toFile().writeText(SCRIPT)
                temporary.toFile().setReadable(true, false)
                Files.move(
                    temporary,
                    file.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } finally {
                Files.deleteIfExists(temporary)
            }
        } catch (_: Exception) {
        }
    }

    /** NODE_OPTIONS naming a missing file would stop every Node program. */
    fun isInstalled(rootfsDir: File): Boolean = try {
        RootfsInfo.guestFile(rootfsDir, GUEST_PATH).let { it.isFile && it.canRead() }
    } catch (_: Exception) {
        false
    }

    /** [existing] options with the shim loaded first, exactly once. */
    fun nodeOptions(existing: String?): String {
        val own = "--require=$GUEST_PATH"
        val rest = existing?.trim().orEmpty()
        if (rest.split(Regex("\\s+")).contains(own)) return rest
        return if (rest.isEmpty()) own else "$own $rest"
    }
}
