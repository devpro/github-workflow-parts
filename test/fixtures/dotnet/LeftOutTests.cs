using Xunit;

namespace Fixture.Tests.LeftOut;

// Fails on purpose, so that the CI job passes only when the test filter excludes this namespace.
public class LeftOutTests
{
    [Fact]
    public void FailsUnlessLeftOut() => Assert.Fail("the test filter did not leave this test out");
}
