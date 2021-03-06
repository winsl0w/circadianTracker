
%NB: needs the function find96WellPlate() in the same folder to work
%as well as image toolbix
%and symbolic math toolbox

clearvars -except handles

%% INPUT VARIABLES

%refStackUpdateTiming=1; % How often to update a ref image, so all ref images updated 7*5 = 35sec
imagingLayer=2; %Channel of the RGB camera to be extracted to follow the movements (green channel, i.e. imagingLayer=1, works the best)
refStackUpdateTime=1/handles.ref_freq; %in s

%Duration of experiment, vibration pattern
handles.exp_duration=handles.exp_duration*60*60; % Convert length of the experiment from hours to seconds
handles.pulse_interval=handles.pulse_interval*60; % Convert min to sec

%Fly position extraction
ROIScale=0.9/2;
speedThresh=50;

%% Save labels and create placeholder files for data

tString = datestr(clock,'mm-dd-yyyy-HH-MM-SS_');
labels = cell2table(labelMaker(handles.labels),'VariableNames',{'Strain' 'Sex' 'Treatment' 'ID' 'Day'});
strain=labels{1,1}{:};
treatment=labels{1,3}{:};
labelID = [handles.fpath '\' tString strain '_' treatment '_labels.dat'];         % File ID for label data
writetable(labels, labelID);                                                % Save label table

% Create placeholder files
cenID = [handles.fpath '\' tString strain '_' treatment '_Centroid.dat'];         % File ID for centroid data
motorID = [handles.fpath '\' tString strain '_' treatment '_Motor.dat'];          % File ID for motor data
areaID = [handles.fpath '\' tString strain '_' treatment '_Area.dat'];         % File ID for centroid data
 
dlmwrite(cenID, []);                                                        % create placeholder ASCII file
dlmwrite(motorID, []);                                                        % create placeholder ASCII file
dlmwrite(areaID, []);                                                        % create placeholder ASCII file

%% Initialize dialogue with Teensy

% Close and delete any open serial objects
if ~isempty(instrfindall)
fclose(instrfindall);           % Make sure that the COM port is closed
delete(instrfindall);           % Delete any serial objects in memory
end

%Initialize vibration parameters
isVibrationOn=0;                                    % Trackings whether current iteration is during a bout of stimulation
isPulseOn=0;                                        % Pulse state from current iteration
wasVibrationOn=0;                                   % tracks whether previous iteration occured during bout of stimulation
wasPulseOn=0;                                       % Pulse state from previous iteration
howManyPulses=0;                                    % Current num. pulses that have occured during a bout of stimulation
howManyVibrations=0;                                % Current num. pulses that have occured during the entire experiment
pulseTime=(1/handles.pulse_frequency)/2;            % Length of time between successive pulses during same bout
pulseDur=(1/handles.pulse_frequency)/2;             % Length of time any given pulse is on
vibrationInterval=handles.pulse_interval;
vibrationDur=handles.pulse_number*(1/handles.pulse_frequency);

%% Determine position in light/dark cycle and initialize white light

t=clock;            % grab current time
t=t(4:5);           % grab hrs and min only

if handles.lights_ON(1)<=t(1) && handles.lights_OFF(1)>=t(1)
    if handles.lights_ON(2)<=t(2)
        writeInfraredWhitePanel(handles.teensy_port,0,handles.White_intensity);
        lightStatus=1;
    else
        writeInfraredWhitePanel(handles.teensy_port,0,0);
        lightStatus=0;
    end
else
        writeInfraredWhitePanel(handles.teensy_port,0,0);
        lightStatus=0;
end

%% Initialize camera
imaqreset;
pause(0.15);
vid=initializeCamera(handles.camInfo);
pause(0.15);
start(vid);
pause(0.15);
%% GET PLATE COORDINATES

im=peekdata(vid,1); % acquire image from camera
im=im(:,:,2); % Extracting the green channel (works the best)
refImage=im;
refStack=repmat(refImage,1,1,handles.ref_stack_size);
fig=imshow(refImage);
set(gca,'Xtick',[],'Ytick',[]);


%% Select tracking threshold

stop=boolean(0);
tic
prev_tStamp=0;

while ~stop
    
    tElapsed=toc;
    im=peekdata(vid,1); % acquire image from camera
    im=squeeze(im(:,:,imagingLayer)); % Extracting the green channel (works the best)
    diffIm=refImage-im;
    pause(0.00001);
    
    % Extract centroids
    
    handles.tracking_thresh=get(handles.threshold_slider,'value');
    props=regionprops((diffIm>handles.tracking_thresh),'Centroid','Area');
    validCentroids=([props.Area]>5&[props.Area]<250);
    cenDat=reshape([props(validCentroids).Centroid],2,length([props(validCentroids).Centroid])/2)';
    
    % Display thresholded image and plot centroids
    %imshow(diffIm>handles.tracking_thresh);
    cla reset
    imagesc(diffIm>handles.tracking_thresh, 'Parent', handles.axes1);
    set(gca,'Xtick',[],'Ytick',[]);
    set(handles.edit_frame_rate,'String',num2str(1/(tElapsed-prev_tStamp)));
    
    hold on
    plot(cenDat(:,1),cenDat(:,2),'o');
    hold off
    stop=boolean(get(handles.accept_thresh_pushbutton,'value'));
    
    prev_tStamp=tElapsed;
    
end

handles.tracking_thresh
set(handles.accept_thresh_pushbutton,'value',0);

%% Detect well positions and permute well numbers to match 96 well plate labels

colormap('gray');
imagesc(im)
[xPlate,yPlate]=getline();
sorted_x=sort(xPlate);
poly_pos=NaN(4,2);
poly_pos(:,1)=xPlate(2:end);
poly_pos(:,2)=yPlate(2:end);
hparent=gca;
h = impoly(hparent, poly_pos);

stop=boolean(0);
h2=[];

while ~stop
    stop=boolean(get(handles.accept_thresh_pushbutton,'value'));

    % Get the plate width in pixels
    plate_bounds=getPosition(h);
    sorted_x=sort(plate_bounds(:,1));
    plate_width=mean(sorted_x(length(sorted_x)-1:length(sorted_x)))-mean(sorted_x([1 2]));
    pix2mm=108.2/plate_width;   % pixel to mm conversion factor (plate width in mm / plate width in pixels)

    isPlateGridPlotted=0;

    hold on
    foundWells=find96WellPlate(im,0,plate_bounds(:,1),plate_bounds(:,2));

    % Permute well number to match 96 well plate
    permute=fliplr(reshape(96:-1:1,8,12)');
    permute=permute(:);
    foundWells.coords=foundWells.coords(permute,:);
    colScale=foundWells.colScale;
    ROISize=round((colScale/7)*ROIScale);
    ROI_centers=round(foundWells.coords);
    
    %cla reset
    %imagesc(im, 'Parent', handles.axes1);
    delete(h2);
    hold on
    h2=viscircles(ROI_centers, repmat(ROISize,size(ROI_centers,1),1));
    hold off
    set(gca,'Xtick',[],'Ytick',[]);
    drawnow

end
set(handles.accept_thresh_pushbutton,'value',0);

lastCentroid=ROI_centers;

centStamp=zeros(size(ROI_centers,1),1);
prevCentroids=lastCentroid;


%% Collect noise statistics and display sample tracking before initiating experiment

ct=1;                               % Frame counter
pixDistSize=100;                    % Num values to record in pixDist
pixelDist=NaN(pixDistSize,1);       % Distribution of total number of pixels above image threshold
tic
tElapsed=toc;

while ct<pixDistSize;
                
               tElapsed=toc;
               set(handles.edit_frame_rate, 'String', num2str(pixDistSize-ct));

               % Get centroids and sort to ROIs
               imagedata=peekdata(vid,1);
               imagedata=imagedata(:,:,imagingLayer);
               diffIm=refImage-imagedata;

               % Extract regionprops and record centroid for blobs with (4 > area > 120) pixels
               props=regionprops((diffIm>handles.tracking_thresh),'Centroid','Area');
               validCentroids=([props.Area]>5&[props.Area]<250);
               
               % Keep only centroids satisfying size constraints and reshape into
               % ROInumber x 2 array
               cenDat=reshape([props(validCentroids).Centroid],2,length([props(validCentroids).Centroid])/2)';
                area=reshape([props(validCentroids).Area],1,length([props(validCentroids).Area]))';

                % Match centroids to ROIs by finding nearest ROI center
                [lastCentroid,centStamp,area]=...
                    optoMatchCentroids2Wells(cenDat,area,ROI_centers,speedThresh,ROISize,lastCentroid,centStamp,tElapsed);
                
               %Update display
               cla reset
               imagesc(diffIm>handles.tracking_thresh, 'Parent', handles.axes1);
               hold on
               % Mark centroids
               plot(lastCentroid(:,1),lastCentroid(:,2),'o','Color','r');
               hold off
               set(gca,'Xtick',[],'Ytick',[]);
               drawnow
               
               
           % Create distribution for num pixels above imageThresh
           % Image statistics used later during acquisition to detect noise
           pixelDist(mod(ct,pixDistSize)+1)=nansum(nansum(imagedata>handles.tracking_thresh));
           ct=ct+1;

end

% Record stdDev and mean without noise
pixStd=nanstd(pixelDist);
pixMean=nanmean(pixelDist);

%% MAIN EXPERIMENTAL LOOP

% Initialize Time Variables
tStart=clock;
tic
counter=1;
ref_counter=1;
tElapsed=toc;
prev_tStamp=toc;
timeBeginning=now;
tSinceLastRefUpdate=0;
pixDev=ones(10,1);                                   % Num Std. of aboveThresh from mean
noiseCt=1;                                           % Frame counter for noise sampling
centStamp=zeros(size(ROI_centers,1),1);
ramp=0;
waitTimes=zeros(1,255);
rampCt=1;
t_ramp=0;
tVibration=0;
isVibrationOn=0;
resetRef=0;
area=NaN(1,size(ROI_centers,1));
iCount=0;

while tElapsed < handles.exp_duration

    % Update timestamp
    tElapsed=toc;
    pause(0.05);
 
        % Grab new image and subtract reference    
        im=peekdata(vid,1);         % acquire image from camera
        im=im(:,:,imagingLayer);            % extract imagingLayer channel
        diffIm=(refImage-im);               % Take difference image

        % Calculate noise level and reset references if noise is too high
        aboveThresh(mod(counter,10)+1)=sum(sum(diffIm>handles.tracking_thresh));
        pixDev(mod(counter,10)+1)=(nanmean(aboveThresh)-pixMean)/pixStd;
        
        % Reset references if noise threshold is exceeded
        if mean(pixDev)>8 || resetRef
           refStack=repmat(im(:,:,1),1,1,handles.ref_stack_size);
           refImage=uint8(mean(double(refStack),3));
           aboveThresh=ones(10,1)*pixMean;
           pixDev=ones(10,1);
           resetRef=0;
           disp('NOISE THRESHOLD REACHED, REFERENCES RESET')
        end
        
        if pixDev(mod(ct,10)+1)<4 && ~isVibrationOn

            % Detect every ref frame update
            if toc-tSinceLastRefUpdate>=refStackUpdateTime
                ref_counter=ref_counter+1;
                refStack(:,:,mod(ref_counter,handles.ref_stack_size)+1)=im;
                refImage=uint8(median(double(refStack),3)); % the actual ref image displayed is the median image of the refstack
                wellCoordinates=round(foundWells.coords);
                colScale=foundWells.colScale;
                ROISize=round((colScale/7)*ROIScale);
                tSinceLastRefUpdate=toc;
            end
            
                % Extract image properties and exclude centroids not satisfying
                % size criteria
                props=regionprops((diffIm>handles.tracking_thresh),'Centroid','Area');
                validCentroids=([props.Area]>7&[props.Area]<250);
                cenDat=reshape([props(validCentroids).Centroid],2,length([props(validCentroids).Centroid])/2)';
                area=reshape([props(validCentroids).Area],1,length([props(validCentroids).Area]))';

                % Match centroids to ROIs by finding nearest ROI center
                [lastCentroid,centStamp,area]=...
                    optoMatchCentroids2Wells(cenDat,area,ROI_centers,speedThresh,ROISize,lastCentroid,centStamp,tElapsed);
                iCount=iCount+1;
        end

%% Update the display
            
        % Write data to the hard drive every third frame to reduce data
        if isempty(area)
            area=NaN(size(lastCentroid,1),1);
        end
        dlmwrite(cenID, single(lastCentroid'), '-append');
        dlmwrite(areaID, single(area'), '-append');

%% Write data to the hardrive 
        format long
        %out(counter,:)=[mod(toc,100) NaN NaN isVibrationOn*isPulseOn reshape(centroidsTemp',1,96*2)];
        %dist=sqrt((lastCentroid(:,1)-prevCentroids(:,1)).^2+(lastCentroid(:,2)-prevCentroids(:,2)).^2);
        dt=tElapsed-prev_tStamp;
        dlmwrite(motorID,[counter single(dt) single(isVibrationOn)],'-append','delimiter','\t','precision',6);

        prevCentroids=lastCentroid;

    
%% Pulse the vibrational motors at the interval specified in the interpulse interval
    if mod(tElapsed,vibrationInterval)<mod(prev_tStamp,vibrationInterval) && ramp==0 && lightStatus==0
        if  tElapsed<handles.exp_duration-0.5
            disp('VIBRATING')
            isVibrationOn=1;
            writeVibrationalMotors(handles.teensy_port,6,handles.pulse_frequency,handles.pulse_interval,...
                handles.pulse_number,handles.pulse_amplitude);
            tVibration=toc;
        end
    end
    
    if isVibrationOn && tElapsed-tVibration>vibrationDur
        isVibrationOn=0;
        resetRef=1;
    end
    
    %% Update light/dark cycle
    
    t=clock;            % grab current time
    t=t(4:5);           % grab hrs and min only

    if lightStatus==1 && t(1)==handles.lights_OFF(1)        % Turn light OFF if light's ON and t > lightsOFF time
        if t(2)==handles.lights_OFF(2)
            lightStatus=0;
            ramp=-1;
            t_ramp=toc;
            rampCt=1;
            waitTimes=logspace(0,2,255);     % Logarithmically increasing wait times for each intensity (totaling 91 min)
        end
    elseif lightStatus==0 && t(1)==handles.lights_ON(1)             % Turn light ON if light's OFF and t > lightsON time
            if t(2)==handles.lights_ON(2) 
                lightStatus=1;
                ramp=1;
                t_ramp=toc;
                rampCt=1;
                waitTimes=max(logspace(0,1.47,255))-logspace(0,1.47,255); % Logarithmically decreasing wait times for each intensity (totaling 91 min)
            end
    end
    
    %% Slowly ramp the light up or down to avoid startling the flies
    
    if ramp~= 0 && tElapsed-t_ramp > waitTimes(rampCt)
        if ramp==1
            writeInfraredWhitePanel(handles.teensy_port,0,uint8(rampCt));
            t_ramp=toc;
            rampCt=rampCt+1;
            disp('ramping up')
            if rampCt > 255
                ramp=0;
                disp('ramping finished');
            end
        end
        if ramp==-1
            writeInfraredWhitePanel(handles.teensy_port,0,uint8(255-rampCt));
            t_ramp=toc;
            rampCt=rampCt+1;
            disp('ramping down')
            if rampCt > 255
                ramp=0;
                disp('ramping finished');
                r_com=1;
            end
        end
    end
    
    %% Update frame counter and timestamp
    %if mod(counter,5)==0
       cla reset
       imagesc(im, 'Parent', handles.axes1);
       hold on
       % Mark centroids
       plot(lastCentroid(:,1),lastCentroid(:,2),'o','Color','r');
       viscircles(ROI_centers, repmat(ROISize,size(ROI_centers,1),1));
       hold off
       set(gca,'Xtick',[],'Ytick',[]);
       drawnow
    %end
    
    set(handles.edit_frame_rate,'String',num2str(1/(tElapsed-prev_tStamp)));
    counter=counter+1;
    prev_tStamp=tElapsed;
    
    % Clear variables to keep memory available
    clearvars im diffIm props validCentroids cenDat speeds dist dt

end


t = clock;
tON = handles.lights_ON;
tOFF = handles.lights_OFF;
m_freq=handles.pulse_frequency;
m_interval=handles.pulse_interval;
m_pulse_number=handles.pulse_number;
m_pulse_amp=handles.pulse_amplitude;
fpath=handles.fpath;

%% Analyze handedness

clearvars -except motorID cenID areaID t tON tOFF m_freq m_interval m_pulse_number m_pulse_amp fpath strain treatment tStart...
    arousal singlePlots tElapsed speed plotData EvenHrIndices timeLabels lightON lightOFF motorON motorOFF labelID pix2mm iCount

% Create a plot of the centroid data as a check on the tracking
cenDat=dlmread(cenID);
cenDat=single(cenDat);
x=cenDat(mod(1:size(cenDat,1),2)==1,:);
y=cenDat(mod(1:size(cenDat,1),2)==0,:);
clearvars cenDat 

% Subsample the data to 1,000 data points per fly
f=round(size(x,1)/1000);
figure();

for i=1:size(x,2)
    hold on
    plot(x(mod(1:size(x,1),f)==0,i),y(mod(1:size(y,1),f)==0,i));
    hold off
end

% Format centroid coords for arena circling processing
centers=single(zeros(size(x,2),2));
centers(:,1)=nanmean(x);
centers(:,2)=nanmean(y);
centroid=single(NaN(size(x,1),size(x,2)*2));
centroid(:,mod(1:size(centroid,2),2)==1)=x;
centroid(:,mod(1:size(centroid,2),2)==0)=y;
clearvars x y

% Extract handedness metrics
cData=flyBurHandData_legacy(centroid,(size(centroid,2)/2),centers);
speed=[cData(:).speed];
clearvars centroid centers

%% Generate population and individual plots

interval=2;         % Width of sliding window in min
stepSize=0.2;       % Incrimental step size of sliding window in min

[dt,tElapsed,speed,plotData,EvenHrIndices,timeLabels,lightON,lightOFF,motorON,motorOFF]=...
    circadianGetPlots(motorID,speed,pix2mm,tStart,tON,tOFF,interval,stepSize);

%% Calculate baseline activity and arousal decay time

if ~isempty(motorON) && ~isempty(motorOFF)
[arousal,singlePlots]=circadianAnalyzeArousalResponse(speed,motorON,motorOFF,tElapsed);
end

% Calculate mu and generate circling plots
for i=1:size(speed,2)
    cData(i).speed=speed(:,i);
end

clearvars dt

area=single(dlmread(areaID));
flyCircles=avgAngle_legacy(cData,[cData(:).width],area);
%circPlotHandTraces(flyCircles,centroid,centers,0);

clearvars cData area

%% Save data to struct

flyTracks.exp='Circadian';
flyTracks.labels=readtable(labelID);
flyTracks.ang_hist=[flyCircles(:).angleavg];
flyTracks.mu=[flyCircles(:).mu];
clearvars flyCircles

flyTracks.pix2mm=pix2mm;
flyTracks.plotData=plotData;
flyTracks.tStamps=tElapsed;
flyTracks.EvenHrIndices=EvenHrIndices;
flyTracks.timeLabels=timeLabels;
flyTracks.activeFlies=nanmean(speed)>0.01;
flyTracks.tLightsON=tON;
flyTracks.tLightsOFF=tOFF;
flyTracks.iLightsON=lightON;
flyTracks.iLightsOFF=lightOFF;
flyTracks.numActive=sum(flyTracks.activeFlies);
flyTracks.speed=speed;
if ~isempty(motorON) && ~isempty(motorOFF)
flyTracks.arousal=arousal;
flyTracks.singlePlots=singlePlots;
end
flyTracks.motorON=motorON;
flyTracks.motorOFF=motorOFF;
flyTracks.experiment_start=tStart;
flyTracks.freq=m_freq;
flyTracks.amp=m_pulse_amp;
flyTracks.interval=m_interval;
flyTracks.nPulse=m_pulse_number;
clearvars -except flyTracks fpath tStart strain treatment
tString=[num2str(tStart(1)) '-' num2str(tStart(2)) '-' num2str(tStart(3)) '-' num2str(tStart(4)) '-' num2str(tStart(5)) '-' num2str(tStart(6))];
save(strcat(fpath,'\',tString,'_',strain,'_',treatment,'_','Circadian.mat'),'flyTracks');
clear

