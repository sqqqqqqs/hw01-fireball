import {mat4, vec3, vec4} from 'gl-matrix';
import Stats from 'stats-js';
import * as DAT from 'dat.gui';
import Icosphere from './geometry/Icosphere';
import Square from './geometry/Square';
import OpenGLRenderer from './rendering/gl/OpenGLRenderer';
import Camera from './Camera';
import {setGL} from './globals';
import ShaderProgram, {Shader} from './rendering/gl/ShaderProgram';

import lambertVertSource from './shaders/lambert-vert.glsl?raw';
import lambertFragSource from './shaders/lambert-frag.glsl?raw';

// values the Reset button snaps back to
const DEFAULTS = {
  tesselations: 5,
  displacementScale: 1.0,
  noiseScale: 1.0,
  mouseStrength: 1.0,
  hotColor: [255, 217, 128] as [number, number, number], // ~ vec3(1.0, 0.85, 0.5)
};

let gui: DAT.GUI;

// Define an object with application parameters and button callbacks
// This will be referred to by dat.GUI's functions that add GUI elements.
const controls = {
  tesselations: DEFAULTS.tesselations,
  displacementScale: DEFAULTS.displacementScale,
  noiseScale: DEFAULTS.noiseScale,
  mouseStrength: DEFAULTS.mouseStrength,
  hotColor: DEFAULTS.hotColor.slice() as [number, number, number],
  'Load Scene': loadScene, // A function pointer, essentially
  'Reset to Defaults': resetToDefaults,
};

function resetToDefaults() {
  controls.tesselations = DEFAULTS.tesselations;
  controls.displacementScale = DEFAULTS.displacementScale;
  controls.noiseScale = DEFAULTS.noiseScale;
  controls.mouseStrength = DEFAULTS.mouseStrength;
  controls.hotColor = DEFAULTS.hotColor.slice() as [number, number, number];
  if (gui) {
    gui.updateDisplay();
  }
}

let icosphere: Icosphere;
let square: Square;
let prevTesselations: number = 5;

// mouse NDC pos + where it hit the fireball (xyz) + whether it's held (w)
let mouseNDC = {x: 0, y: 0};
let mouseDown = false;
let mouseWorld = vec4.fromValues(0, 0, 0, 0);

// radius for the mouse ray hit test -- close to the base radius so it lands near the real bumpy surface
const MOUSE_SPHERE_RADIUS = 1.1;

// ray-sphere hit test, sphere centered at origin -- nearest hit, or null if it misses
function raySphereIntersect(origin: vec3, dir: vec3, radius: number): vec3 | null {
  const oc = vec3.create();
  vec3.copy(oc, origin);
  const a = vec3.dot(dir, dir);
  const b = 2.0 * vec3.dot(oc, dir);
  const c = vec3.dot(oc, oc) - radius * radius;
  const disc = b * b - 4 * a * c;
  if (disc < 0) {
    return null;
  }
  const sqrtDisc = Math.sqrt(disc);
  const t0 = (-b - sqrtDisc) / (2 * a);
  const t1 = (-b + sqrtDisc) / (2 * a);
  const t = t0 >= 0 ? t0 : t1;
  if (t < 0) {
    return null;
  }
  const hit = vec3.create();
  vec3.scaleAndAdd(hit, origin, dir, t);
  return hit;
}

function loadScene() {
  icosphere = new Icosphere(vec3.fromValues(0, 0, 0), 1, controls.tesselations);
  icosphere.create();
  square = new Square(vec3.fromValues(0, 0, 0));
  square.create();
}

function main() {
  // Initial display for framerate
  const stats = Stats();
  stats.setMode(0);
  stats.domElement.style.position = 'absolute';
  stats.domElement.style.left = '0px';
  stats.domElement.style.top = '0px';
  document.body.appendChild(stats.domElement);

  // Add controls to the gui
  gui = new DAT.GUI();
  gui.add(controls, 'tesselations', 0, 8).step(1);
  gui.add(controls, 'displacementScale', 0, 2).step(0.05).name('Displacement');
  gui.add(controls, 'noiseScale', 0.3, 3).step(0.05).name('Noise Scale');
  gui.add(controls, 'mouseStrength', 0, 2).step(0.05).name('Mouse Strength');
  gui.addColor(controls, 'hotColor').name('Hot Color');
  gui.add(controls, 'Load Scene');
  gui.add(controls, 'Reset to Defaults');

  // get canvas and webgl context
  const canvas = <HTMLCanvasElement> document.getElementById('canvas');
  const gl = <WebGL2RenderingContext> canvas.getContext('webgl2');
  if (!gl) {
    alert('WebGL 2 not supported!');
  }
  // `setGL` is a function imported above which sets the value of `gl` in the `globals.ts` module.
  // Later, we can import `gl` from `globals.ts` to access it
  setGL(gl);

  // Initial call to load scene
  loadScene();

  const camera = new Camera(vec3.fromValues(0, 0, 5), vec3.fromValues(0, 0, 0));

  const renderer = new OpenGLRenderer(canvas);
  renderer.setClearColor(0.2, 0.2, 0.2, 1);
  gl.enable(gl.DEPTH_TEST);

  const lambert = new ShaderProgram([
    new Shader(gl.VERTEX_SHADER, lambertVertSource),
    new Shader(gl.FRAGMENT_SHADER, lambertFragSource),
  ]);

  const startTime = performance.now();

  // just converts pixel coords to NDC
  function updateMouseNDC(clientX: number, clientY: number) {
    const rect = canvas.getBoundingClientRect();
    mouseNDC.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    mouseNDC.y = -(((clientY - rect.top) / rect.height) * 2 - 1);
  }

  canvas.addEventListener('mousemove', function(event: MouseEvent) {
    updateMouseNDC(event.clientX, event.clientY);
  });
  canvas.addEventListener('mousedown', function(event: MouseEvent) {
    updateMouseNDC(event.clientX, event.clientY);
    mouseDown = true;
  });
  window.addEventListener('mouseup', function() {
    mouseDown = false;
  });

  // shoots a ray through the mouse pos and sees where it hits the fireball
  function updateMouseWorld() {
    if (!mouseDown) {
      mouseWorld[3] = 0;
      return;
    }

    const invViewProj = mat4.create();
    const viewProj = mat4.create();
    mat4.multiply(viewProj, camera.projectionMatrix, camera.viewMatrix);
    if (!mat4.invert(invViewProj, viewProj)) {
      mouseWorld[3] = 0;
      return;
    }

    const nearPoint = vec4.fromValues(mouseNDC.x, mouseNDC.y, -1, 1);
    const farPoint = vec4.fromValues(mouseNDC.x, mouseNDC.y, 1, 1);
    vec4.transformMat4(nearPoint, nearPoint, invViewProj);
    vec4.transformMat4(farPoint, farPoint, invViewProj);
    vec4.scale(nearPoint, nearPoint, 1 / nearPoint[3]);
    vec4.scale(farPoint, farPoint, 1 / farPoint[3]);

    const rayOrigin = vec3.fromValues(nearPoint[0], nearPoint[1], nearPoint[2]);
    const rayTarget = vec3.fromValues(farPoint[0], farPoint[1], farPoint[2]);
    const rayDir = vec3.create();
    vec3.subtract(rayDir, rayTarget, rayOrigin);
    vec3.normalize(rayDir, rayDir);

    const hit = raySphereIntersect(rayOrigin, rayDir, MOUSE_SPHERE_RADIUS);
    if (hit) {
      mouseWorld[0] = hit[0];
      mouseWorld[1] = hit[1];
      mouseWorld[2] = hit[2];
      mouseWorld[3] = 1;
    } else {
      mouseWorld[3] = 0;
    }
  }

  // This function will be called every frame
  function tick() {
    camera.update();
    stats.begin();
    gl.viewport(0, 0, window.innerWidth, window.innerHeight);
    renderer.clear();
    if(controls.tesselations != prevTesselations)
    {
      prevTesselations = controls.tesselations;
      icosphere = new Icosphere(vec3.fromValues(0, 0, 0), 1, prevTesselations);
      icosphere.create();
    }
    updateMouseWorld();
    const elapsedTime = (performance.now() - startTime) / 1000;
    const fireballParams = {
      displacementScale: controls.displacementScale,
      noiseScale: controls.noiseScale,
      mouseStrength: controls.mouseStrength,
      hotColor: vec3.fromValues(
        controls.hotColor[0] / 255,
        controls.hotColor[1] / 255,
        controls.hotColor[2] / 255,
      ),
    };
    renderer.render(camera, lambert, [
      icosphere,
      // square,
    ], elapsedTime, mouseWorld, fireballParams);
    stats.end();

    // Tell the browser to call `tick` again whenever it renders a new frame
    requestAnimationFrame(tick);
  }

  window.addEventListener('resize', function() {
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.setAspectRatio(window.innerWidth / window.innerHeight);
    camera.updateProjectionMatrix();
  }, false);

  renderer.setSize(window.innerWidth, window.innerHeight);
  camera.setAspectRatio(window.innerWidth / window.innerHeight);
  camera.updateProjectionMatrix();

  // Start the render loop
  tick();
}

main();
