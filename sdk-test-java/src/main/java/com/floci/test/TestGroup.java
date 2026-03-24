package com.floci.test;

/**
 * A named group of related SDK tests.
 * <p>
 * The {@link #name()} is used to select groups via CLI args or the
 * {@code FLOCI_TESTS} environment variable (comma-separated).
 */
public interface TestGroup {

    /** Short identifier used for group selection, e.g. {@code "sqs"}, {@code "s3"}. */
    String name();

    /** Execute all checks in this group, recording results in {@code ctx}. */
    void run(TestContext ctx);
}
