using Xunit;

namespace Fixture.Tests.LeftOut;

// Fails on purpose: the CI job passes only when dotnet-test-filter leaves this namespace out.
public class LeftOutTests
{
    [Fact]
    public void FailsUnlessLeftOut() => Assert.Fail("dotnet-test-filter did not leave this test out");
}
