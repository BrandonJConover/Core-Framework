import React from "react";
import { Game } from "../osrs/Game";
import { Configuration } from "../osrs/Configuration";

export class WebScape extends React.Component {
    static game: Game = null;
    state = { game: null };
    private canvasRef = React.createRef<HTMLCanvasElement>();

    componentDidMount() {
        const canvas = this.canvasRef.current;
        canvas.focus();
        const curGame = new Game(canvas);
        WebScape.game = curGame;
        (window as any).__webscapeGame = curGame;
        const credentials = (window as any).__webscapeCredentials;
        const server = (window as any).__webscapeServer;
        if (server) {
            if (typeof server.host === "string") Configuration.SERVER_ADDRESS = server.host;
            if (typeof server.port === "number") Configuration.GAME_PORT = server.port;
            if (typeof server.dialect === "string") Configuration.OUTGOING_DIALECT = server.dialect;
        }
        if (credentials) {
            if (typeof credentials.username === "string") curGame.username = credentials.username;
            if (typeof credentials.password === "string") curGame.password = credentials.password;
        }
        curGame.initializeApplication(canvas.width, canvas.height).then(() => {
            if (credentials && credentials.autoLogin && typeof credentials.username === "string" && typeof credentials.password === "string") {
                curGame.login(credentials.username, credentials.password, false);
            }
        });
    }

    render() {
        return (
            <div className="webscape-stage">
                <canvas
                    className="webscape-canvas"
                    ref={this.canvasRef}
                    width={765}
                    height={503}
                    tabIndex={1}
                    onContextMenu={(mouseEvent) => {
                        mouseEvent.preventDefault();
                    }}
                />
            </div>
        );
    }
}
