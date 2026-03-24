package com.floci.test.tests;

import java.nio.charset.StandardCharsets;

/** Shared Lambda deployment-package helpers. */
public class LambdaUtils {

    /**
     * ZIP containing a Node.js handler that greets by name and echoes the event.
     */
    public static byte[] handlerZip() {
        String code = """
                exports.handler = async (event) => {
                    const name = (event && event.name) ? event.name : 'World';
                    console.log('[handler] invoked with event:', JSON.stringify(event));
                    console.log('[handler] resolved name:', name);
                    const response = {
                        statusCode: 200,
                        body: JSON.stringify({ message: `Hello, ${name}!`, input: event })
                    };
                    console.log('[handler] returning response:', JSON.stringify(response));
                    return response;
                };
                """;
        try {
            var baos = new java.io.ByteArrayOutputStream();
            try (var zos = new java.util.zip.ZipOutputStream(baos)) {
                zos.putNextEntry(new java.util.zip.ZipEntry("index.js"));
                zos.write(code.getBytes(StandardCharsets.UTF_8));
                zos.closeEntry();
            }
            return baos.toByteArray();
        } catch (Exception e) {
            throw new RuntimeException("Failed to build handler ZIP", e);
        }
    }

    /**
     * Minimal valid ZIP containing a stub {@code index.js} — accepted by the emulator
     * without needing a real runtime.
     */
    public static byte[] minimalZip() {
        String code = """
                exports.handler = async (event) => {
                    console.log('[esm-handler] invoked with event:', JSON.stringify(event));
                    return { statusCode: 200, body: 'ok' };
                };
                """;
        try {
            var baos = new java.io.ByteArrayOutputStream();
            try (var zos = new java.util.zip.ZipOutputStream(baos)) {
                zos.putNextEntry(new java.util.zip.ZipEntry("index.js"));
                zos.write(code.getBytes(StandardCharsets.UTF_8));
                zos.closeEntry();
            }
            return baos.toByteArray();
        } catch (Exception e) {
            throw new RuntimeException("Failed to build minimal ZIP", e);
        }
    }
}
