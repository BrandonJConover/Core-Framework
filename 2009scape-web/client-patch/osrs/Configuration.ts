export class Configuration {
    // Server address: replaced at deploy time. Default is loopback for local dev;
    // production deployments override this in setup.sh / docker-compose.yml.
    public static SERVER_ADDRESS: string = "10.8.0.1";
    public static GAME_PORT: number = 43601;
    public static OUTGOING_DIALECT: string = "530";
    public static JAGGRAB_PORT: number = 43601;
    public static HTTP_PORT: number = 8080;
    public static JAGGRAB_ENABLED: boolean = false;
    public static RSA_ENABLED: boolean = true;
    public static RSA_PUBLIC_KEY: string = "65537";
    public static RSA_MODULUS: string = "96982303379631821170939875058071478695026608406924780574168393250855797534862289546229721580153879336741968220328805101128831071152160922518190059946555203865621183480223212969502122536662721687753974815205744569357388338433981424032996046420057284324856368815997832596174397728134370577184183004453899764051";
    public static CACHE_INDEX_COUNT: number = 29;
    /** Client build revision sent in the login handshake. 530 = 2009scape rt4. */
    public static CLIENT_REVISION: number = 530;
    /** Default rendering canvas dimensions (resizable mode picks its own). */
    public static DEFAULT_WIDTH: number = 765;
    public static DEFAULT_HEIGHT: number = 503;
}
