import { BasePolyfiller } from "./base-polyfiller";
import { polyfillRegistry } from "./registry";

const getPolyfillers = (version: number) => {
  const polyfillers: {version: number, polyfiller: BasePolyfiller}[] = [];
  for (const [pVersion, polyfillerCls] of polyfillRegistry.entries()) {
    if (version <= pVersion) { 
      polyfillers.push({ version: pVersion, polyfiller: new polyfillerCls() });
    }
  }
  polyfillers.sort((a, b) => a.version - b.version);
  return polyfillers.map(p => p.polyfiller);
}


export async function polyfillGameMsg(version: number, msgTitle: string, buffer: Buffer) {
  return undefined;
}

export async function polyfillResponse(version: number, msgTitle: string, buffer: Buffer) {
  return;
}
