import React from "react";
import { hot } from "react-hot-loader";
import { WebScape } from "./WebScape";

const App = () => {
    return (
        <div className="web-client-root">
            <style>{`
                html, body, #root {
                    width: 100%;
                    height: 100%;
                    margin: 0;
                    overflow: hidden;
                    background: #050505;
                    overscroll-behavior: none;
                }

                * {
                    box-sizing: border-box;
                }

                .web-client-root {
                    position: fixed;
                    inset: 0;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    width: 100vw;
                    height: 100vh;
                    height: 100dvh;
                    min-height: -webkit-fill-available;
                    background: #050505;
                    overflow: hidden;
                    touch-action: none;
                }

                .webscape-stage {
                    width: min(100vw, calc(100vh * 765 / 503));
                    height: min(100vh, calc(100vw * 503 / 765));
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    background: #000;
                    overflow: hidden;
                    touch-action: none;
                }

                .webscape-canvas {
                    display: block;
                    width: 100%;
                    height: 100%;
                    border: 0;
                    outline: none;
                    background: #000;
                    image-rendering: pixelated;
                    touch-action: none;
                    user-select: none;
                    -webkit-user-select: none;
                    -webkit-touch-callout: none;
                }

                @media (orientation: portrait) {
                    .web-client-root {
                        align-items: flex-start;
                    }
                }
            `}</style>
            <WebScape />
        </div>
    );
};

export default hot(module)(App);
