using Newtonsoft.Json;

namespace Fixture.Framework.Library
{
    public static class Greeting
    {
        // Uses a package from packages.config, so that the build fails if the restore skips it.
        public static string ToJson(string name)
        {
            return JsonConvert.SerializeObject(new { message = "Hello " + name });
        }
    }
}
