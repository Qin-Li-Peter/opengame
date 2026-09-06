using BepInEx;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.Rendering;
using System;
using System.IO;
using System.Collections.Generic;
using System.Diagnostics;
[BepInPlugin("local.opengame.telemetry", "OpenGame Telemetry Recorder", "1.0")]
public class Telemetry : BaseUnityPlugin {
 readonly List<double> frameTimes=new List<double>();
 int renderedFrames,lastRendered=-1;
 void Rendered(){if(Time.frameCount!=lastRendered){lastRendered=Time.frameCount;renderedFrames++;}}
 void CameraDone(Camera camera){Rendered();}
 void PipelineDone(ScriptableRenderContext context,Camera[] cameras){Rendered();}
 void OnDestroy(){Camera.onPostRender-=CameraDone;RenderPipelineManager.endFrameRendering-=PipelineDone;}
 double start,last;string run;bool measured,finished,configured;
 void Awake(){
  Camera.onPostRender+=CameraDone;RenderPipelineManager.endFrameRendering+=PipelineDone;
  run=Environment.GetEnvironmentVariable("OG_BENCH_RUN") ?? "manual";
  Application.runInBackground=true;QualitySettings.vSyncCount=0;Application.targetFrameRate=-1;
  QualitySettings.SetQualityLevel(Math.Min(2,QualitySettings.names.Length-1),true);
  Screen.SetResolution(1280,720,false);
  start=Clock();last=start;
  Logger.LogInfo("PERF_RECORDER_READY "+run);
 }
 System.Collections.IEnumerator StopAfterCapture(){yield return new WaitForSecondsRealtime(2);Application.Quit();}
 static double Clock(){return (double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;}
 void Update(){
  if(finished)return;
  double now=Clock();double dt=now-last;last=now;
  if(!configured && now-start>5){configured=true;QualitySettings.SetQualityLevel(Math.Min(2,QualitySettings.names.Length-1),true);QualitySettings.vSyncCount=0;Application.targetFrameRate=-1;Screen.SetResolution(1280,720,false);}
  if(now-start<25)return;
  if(!measured){measured=true;renderedFrames=0;last=now;return;}
  frameTimes.Add(dt*1000);
  if(now-start<70)return;
  finished=true;
  var lines=new List<string>();
  lines.Add("frame_ms");foreach(double t in frameTimes)lines.Add(t.ToString("F6",System.Globalization.CultureInfo.InvariantCulture));
  File.WriteAllLines("perf-"+run+".csv",lines.ToArray());
  File.WriteAllText("perf-"+run+"-info.txt", "run="+run+"\nscene="+SceneManager.GetActiveScene().name+"\nresolution="+Screen.width+"x"+Screen.height+"\nquality="+QualitySettings.GetQualityLevel()+"\nvSync="+QualitySettings.vSyncCount+"\ntargetFrameRate="+Application.targetFrameRate+"\nrenderedFrames="+renderedFrames+"\nframes="+frameTimes.Count+"\napi="+SystemInfo.graphicsDeviceType+"\ngpu="+SystemInfo.graphicsDeviceName+"\n");
  Logger.LogInfo("PERF_RECORDER_COMPLETE "+run+" frames="+frameTimes.Count);
  ScreenCapture.CaptureScreenshot("perf-"+run+".png");
  StartCoroutine(StopAfterCapture());
 }
}
