using Newtonsoft.Json;

namespace Fixture.Framework.Library
{
    public static class Greeting
    {
        // A package restored from packages.config is used, so a restore that skips it fails the build.
        public static string ToJson(string name)
        {
            return JsonConvert.SerializeObject(new { message = "Hello " + name });
        }
    }
}
