using Fixture.Framework.Library;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Fixture.Framework.Tests
{
    [TestClass]
    public class GreetingTests
    {
        [TestMethod]
        public void ToJson_WritesTheMessage()
        {
            Assert.AreEqual("{\"message\":\"Hello world\"}", Greeting.ToJson("world"));
        }
    }
}
