function neuron
    version = '0.3';
    
    CONST_FILEFORMAT_UNKNOWN = 0;
    CONST_FILEFORMAT_BIOFORMATS = 1; %bioformats
    CONST_FILEFORMAT_SINGLETIFF = 2; %TIFF, multiple files, one frame per file
    CONST_FILEFORMAT_XML = 3; %xml (PrairieView format, with each frame represented by a pointer to an individual single-image tif file)
        
    CONST_BEHAVIOUR_UNKNOWN = 1;
    CONST_BEHAVIOUR_STATIONARY = 2;
    CONST_BEHAVIOUR_FORWARDS = 3;
    CONST_BEHAVIOUR_REVERSAL = 4;
    CONST_BEHAVIOUR_INVALID = 5;
    CONST_BEHAVIOUR_BADFRAME = 6;
    CONST_BEHAVIOUR_SHORTINTERVAL = 7;
    
    CONST_BUTTON_NONE = 0;
    CONST_BUTTON_FORWARDS = -1;
    CONST_BUTTON_STATIONARY = -2;
    CONST_BUTTON_REVERSAL = -3;
    CONST_BUTTON_INVALID = -4;
    CONST_BUTTON_ABORT = -5;
    
    readableextensions = {'*.xml', '*.stk', '*.avi', '*.tif', '*.mp4', '*.mov', '*.wmv', '*.tiff', '*.nd2', '*.ics'};
    
    currentpath = cd;
    files = [];
    file = [];
    newfile = [];
    leftcache = []; %actual contents of the cache
    rightcache = [];
    leftcached = 0; %which frame is cached
    rightcached = 0;

    circlepointsx=cos((0:30)*2*pi/30); %how smooth the drawn circles will be. these values will be scaled by the radius, displaced by the center coordinates, and connected with a plot to draw a circle
    circlepointsy=sin((0:30)*2*pi/30);

    nf = 0; % Number of frames
    nf1 = 0; % Number of frames in the first file of a dualmovie
    frame = 1;
    fileformat = CONST_FILEFORMAT_UNKNOWN;
    stackcache = 0; %Where everything is cached for stacks. NaN if nothing is cached
    dontupdatevisibility = false;
    dontupdateframe = false;
    currentlycalculating = false;
    currentlyselected = false;
    leftthreshold = 0;
    rightthreshold = 0;
    waitbarfps = 20;
    
    rightdisplacementx = NaN;
    rightdisplacementy = NaN;
    originalsizex = NaN;
    originalsizey = NaN;
    
    %correction factors appropriate for Optosplit with Cascade II
    correctionfactorA = 0.900; %for TuCam with (475;478);(535;550) filters: 0.673
    correctionfactorB = 0.776; %for TuCam with (475;478);(535;550) filters: 0.958
    
    excludedarea = [];
    
    pixelnumber = 20;
    percentile = 10; %lowest this percentile of the pixels in consideration is taken as the background
    offset = 1050;
    minimalneuronsize = 5;
    correctionsearchradius = 0; % Looking locally for the peak in the two channels
    alignmentsearchradius = 8; % Looking locally for the peak in the two channels at the time of the user-defined global alignment
    gaussianx = 3;
    gaussiany = 3;
    gaussians = 0.5;
    gaussianfilter = fspecial('gaussian',[gaussianx,gaussiany],gaussians); %Gaussian filter to help find continuous areas
    movingaverage = 1;
    radius = 1.0;
    maxnumberofregions = 0;
    numberofregionsfound = 0;
    ratios = [];
    leftvalues = [];
    rightvalues = [];
    leftbackground = [];
    rightbackground = [];
    rationames = [];
    
    arbarea = [];
    
    frametime = [];
    framex = [];
    framey = [];
    
    behaviour = [];
    usingbehaviour = false;
    
    leftregionx = [];
    leftregiony = [];
    leftregionz = [];
    rightregionx = [];
    rightregiony = [];
    rightregionz = [];
    regionimportant = [];
    regionname = [];
    leftregionradius = [];
    rightregionradius = [];
    numberofregions = []; % this is per frame, i.e. how many regions were found in that particular frame
    
    cropleft = 0;
    cropright = 0;
    croptop = 0;
    cropbottom = 0;
    leftwidth = NaN;
    unusablerightx = 0;
    subchannelsizex = 0;
    subchannelsizey = 0;
    
    selectedregion = 0;
    selectedname = '-----'; %meaning that name is unavailable as no neuron is selected
    selectedradiusy = 0;
    selectedradiusc = 0;

    detectpressed = false;
    detectcrosshairpoint = NaN;
    detectcrosshairtop = NaN; %top of the cursor
    detectcrosshairbottom = NaN; %bottom of the cursor
    detectcrosshairleft = NaN; %left of the cursor
    detectcrosshairright = NaN; %right of the cursor
	trackingleft = false;
    
    movieFPS = 10;
    moviemaxduration = 3;
    whichbuttonpressed = NaN;
    
    detectedframes = [];
    detectedneurons = [];
    
    speedreadable = false;
    
    bfreader = [];
    stack3d = false;
    stacktucam = false;
    stacktucamflipx1 = false;
    stacktucamflipy1 = false;
    stacktucamflipx2 = false;
    stacktucamflipy2 = false;
    xmlstruct = [];
    maxproject = false;
    uniqueposz = [];
    zpos1 = [];
    tindex1 = []; %in a 3d stack, for each absolute frame (tiff image in sequence) which t-index does it correspond to (one sweep through the z-coordinates == 1 t-index)
    tindex2 = []; %same for the second tiff in a 3d dualstack
    rotatestack = false;
    
    % Main figure
    handles.fig = figure('Name',['Ratiometric Imaging Movie Analyser ' version],'NumberTitle','off', ...
        'Visible','off','Color',get(0,'defaultUicontrolBackgroundColor'),...%'Toolbar','none','Menubar','none',...
        'DeleteFcn', @savesettings);

    %File selection panel
    handles.datapanel = uipanel(handles.fig,'Title','File selection','Units','Normalized',...
        'DefaultUicontrolUnits','Normalized','Position',[0 0.27 0.30 0.73]);
    handles.folder = uicontrol(handles.datapanel,'Style','Edit','String',currentpath,...
        'HorizontalAlignment','left','BackgroundColor','w',...
        'Position',[0.00 0.95 0.60 0.05],'Callback',@updatefilelist);
    handles.rotatestack = uicontrol(handles.datapanel, 'Style','Checkbox','String','Rotate',...
        'Position',[0.60 0.95 0.10 0.05],'Callback',{@setvalue, 'setglobal', 'rotate', 'logical', 'setglobal', 'rotatestack'});
    handles.updatefiles = uicontrol(handles.datapanel, 'Style','Pushbutton','String','Refresh',...
        'Position',[0.70 0.95 0.15 0.05],'Callback',@updatefilelist);
    handles.browse = uicontrol(handles.datapanel,'Style','Pushbutton','String','Browse',...
        'Position',[0.85 0.95 0.15 0.05],'Callback',@browse);
    handles.files = uicontrol(handles.datapanel,'Style','Listbox','String',files,...
        'BackgroundColor','w',...
        'Position',[0.00 0.00 1.00 0.95],'Callback',@selectfile);
    
    %Saving and loading
    handles.savepanel = uipanel(handles.fig,'Title','Load or save data','Units','Normalized',...
        'DefaultUicontrolUnits','Normalized','Position',[0 0.18 0.30 0.09]);
    handles.load = uicontrol(handles.savepanel,'Style','Pushbutton','String','Load movie',...
        'Position',[0.00 0.00 0.20 1.00],'Callback',@loadstack,'Enable','off');
    handles.readspeed = uicontrol(handles.savepanel,'Style','Pushbutton','String','Read speed',...
        'Position',[0.21 0.00 0.20 1.00],'Callback',@readspeed,'Enable','off');
    handles.loadanalysis = uicontrol(handles.savepanel,'Style','Pushbutton','String','Load analysis',...
        'Position',[0.45 0.00 0.18 1.00],'Callback',@loadanalysis,'Enable','off');    
    handles.saveanalysis = uicontrol(handles.savepanel,'Style','Pushbutton','String','Save analysis',...
        'Position',[0.64 0.00 0.18 1.00],'Callback',@saveanalysis,'Enable','off');
    handles.exportdataaslog = uicontrol(handles.savepanel,'Style','Pushbutton','String','Export as log',...
        'Position',[0.85 0.50 0.15 0.50],'Callback',@exportdataaslog,'Enable','off');
    handles.exportdataastxt = uicontrol(handles.savepanel,'Style','Pushbutton','String','Export as txt',...
        'Position',[0.85 0.00 0.15 0.50],'Callback',@exportdataastxt,'Enable','off');

    %Cropping and alignment
    handles.definepanel = uipanel(handles.fig,'Title','Setup analysis area','Units','Normalized',...
        'DefaultUicontrolUnits','Normalized','Position',[0 0.00 0.30 0.18]);
    
    handles.subchannelsizedisplaytexttop = uicontrol(handles.definepanel,'Style', 'Text', 'String', 'Channels:','FontWeight','demi',...
        'Position',[0.00 0.87 0.21 0.10]);
    handles.subchannelsizedisplay = uicontrol(handles.definepanel,'Style', 'Text', 'String', '0x0','FontWeight','bold',...
        'Position',[0.00 0.77 0.21 0.10]);
    handles.subchannelsizedisplaytextbottom = uicontrol(handles.definepanel,'Style', 'Text', 'String', 'pixels','FontWeight','demi',...
        'Position',[0.00 0.67 0.21 0.10]);
    handles.setcropall = uicontrol(handles.definepanel, 'Style', 'Pushbutton', 'String', 'Set cropping',...
       'Position',[0.00 0.00 0.21 0.30], 'Callback', @setcropall);
    
    handles.croplefttext = uicontrol(handles.definepanel, 'Style', 'Text', 'String', 'Left crop', ...
        'Position',[0.00 0.55 0.21 0.10]);
    handles.cropleft = uicontrol(handles.definepanel, 'Style', 'Edit', 'String', num2str(cropleft), ...
        'Position',[0.00 0.35 0.21 0.20], 'Callback', @setcropleft);
    handles.croptoptext = uicontrol(handles.definepanel, 'Style', 'Text', 'String', 'Top crop', ...
        'Position',[0.26 0.90 0.21 0.10]);
    handles.croptop = uicontrol(handles.definepanel, 'Style', 'Edit', 'String', num2str(croptop), ...
        'Position',[0.26 0.70 0.21 0.20], 'Callback', @setcroptop);
    handles.cropbottomtext = uicontrol(handles.definepanel, 'Style', 'Text', 'String', 'Bottom crop', ...
        'Position',[0.26 0.20 0.21 0.10]);
    handles.cropbottom = uicontrol(handles.definepanel, 'Style', 'Edit', 'String', num2str(cropbottom), ...
        'Position',[0.26 0.00 0.21 0.20], 'Callback', @setcropbottom);
    handles.cropmiddletext = uicontrol(handles.definepanel, 'Style', 'Text', 'String', 'Channel division', ...
        'Position',[0.26 0.55 0.21 0.10]);
    handles.croplmiddle = uicontrol(handles.definepanel, 'Style', 'Edit', 'String', num2str(leftwidth), ...
        'Position',[0.26 0.35 0.10 0.20], 'Callback', @setcroplmiddle);
    handles.croprmiddle = uicontrol(handles.definepanel, 'Style', 'Edit', 'String', num2str(rightdisplacementx+unusablerightx), ...
        'Position',[0.37 0.35 0.10 0.20], 'Callback', @setcroprmiddle);
    handles.croprighttext = uicontrol(handles.definepanel, 'Style', 'Text', 'String', 'Right crop', ...
        'Position',[0.52 0.55 0.21 0.10]);
    handles.cropright = uicontrol(handles.definepanel, 'Style', 'Edit', 'String', num2str(cropright), ...
        'Position',[0.52 0.35 0.21 0.20], 'Callback', @setcropright);
    
    handles.alignmentsearchradiusdisplay = uicontrol(handles.definepanel,'Style','Text','String','Alignment search',...
        'Position',[0.47 0.90 0.31 0.10]);
    handles.alignmentsearchradius = uicontrol(handles.definepanel,'Style','Edit','String',num2str(alignmentsearchradius),...
        'Position',[0.52 0.70 0.21 0.20],'Callback',@setalignmentsearchradius);
    
    handles.alignmentdisplaytext1 = uicontrol(handles.definepanel,'Style', 'Text', 'String', 'Alignment',... %first line
        'Position',[0.78 0.85 0.21 0.10]);
    handles.alignmentdisplaytext2 = uicontrol(handles.definepanel,'Style', 'Text', 'String', 'vector:',... %second line
        'Position',[0.78 0.75 0.21 0.10]);
    handles.alignmentdisplaytextx = uicontrol(handles.definepanel,'Style', 'Text', 'String', 'x',...
        'Position',[0.78 0.65 0.10 0.10]);
    handles.alignmentx = uicontrol(handles.definepanel,'Style', 'Edit', 'String', num2str(rightdisplacementx),...
        'Position',[0.78 0.45 0.10 0.20], 'Callback',@setrightdisplacementx);
    handles.alignmentdisplaytexty = uicontrol(handles.definepanel,'Style', 'Text', 'String', 'y',...
        'Position',[0.89 0.65 0.10 0.10]);
    handles.alignmenty = uicontrol(handles.definepanel,'Style', 'Edit', 'String', num2str(rightdisplacementy),...
        'Position',[0.89 0.45 0.10 0.20], 'Callback',@setrightdisplacementy);
    
    handles.setcropmiddle = uicontrol(handles.definepanel, 'Style', 'Pushbutton', 'String', 'Set division', ...
        'Position',[0.52 0.00 0.21 0.30], 'Callback', @setcropmiddle);
    handles.setalignment = uicontrol(handles.definepanel,'Style','Pushbutton','String','Set alignment',...
        'Position',[0.78 0.00 0.21 0.40],'Callback',@setalignment);

    %Neuron detection
    handles.detectpanel = uipanel(handles.fig,'Title','Neuron detection','Units','Normalized',...
        'DefaultUicontrolUnits','Normalized','Position',[0.70 0.70 0.30 0.30]);
    handles.correctionsearchradiustext = uicontrol(handles.detectpanel,'Style','Text','String','Search radius',...
        'Position',[0.00 0.85 0.23 0.10]);
    handles.correctionsearchradius = uicontrol(handles.detectpanel,'Style','Edit','String',num2str(correctionsearchradius),...
        'Position',[0.00 0.70 0.23 0.15],'Callback',@setcorrectionsearchradius);
    handles.minimalneuronsizetext = uicontrol(handles.detectpanel,'Style','Text','String','Minimal neuron size',...
        'Position',[0.27 0.85 0.23 0.10]);
    handles.minimalneuronsize = uicontrol(handles.detectpanel,'Style','Edit','String',num2str(minimalneuronsize),...
        'Position',[0.27 0.70 0.23 0.15],'Callback',@setminimalneuronsize);
    handles.filtertext = uicontrol(handles.detectpanel,'Style','Text','String','Filter size and sigma',...
        'Position',[0.54 0.85 0.23 0.10]);
    handles.filter = uicontrol(handles.detectpanel,'Style','Edit','String',['[' num2str(gaussianx) ' ' num2str(gaussiany) '], ' num2str(gaussians)],...
        'Position',[0.54 0.70 0.23 0.15],'Callback',@setfilter);
    
    handles.excludedarea = uicontrol(handles.detectpanel, 'Style', 'Pushbutton', 'String', 'Exclude',...
        'Position',[0.77 0.70 0.13 0.30],'Callback',@setexcludedarea);
    handles.saturationcheck = uicontrol(handles.detectpanel, 'Style', 'Pushbutton', 'String', 'Max',...
        'Position',[0.90 0.85 0.10 0.15],'Callback',@saturationcheck);
    handles.mediancheck = uicontrol(handles.detectpanel, 'Style', 'Pushbutton', 'String', 'Median',...
        'Position',[0.90 0.70 0.10 0.15],'Callback',@mediancheck);
    handles.leftthresholdtext = uicontrol(handles.detectpanel,'Style', 'Text', 'String', 'Left threshold',...
        'Position',[0.00 0.55 0.23 0.07]);
    handles.leftthresholdbox = uicontrol(handles.detectpanel, 'Style', 'Edit', 'String', num2str(0), ...
        'Position',[0.00 0.40 0.23 0.15],'Callback',{@setvalue, 'setglobal', 'leftthreshold', 'min', 0, 'showit'});
    handles.rightthresholdtext = uicontrol(handles.detectpanel,'Style', 'Text', 'String', 'Right threshold',...
        'Position',[0.27 0.55 0.23 0.07]);    
    handles.rightthresholdbox = uicontrol(handles.detectpanel, 'Style', 'Edit', 'String', num2str(0), ...
        'Position',[0.27 0.40 0.23 0.15],'Callback',{@setvalue, 'setglobal', 'rightthreshold', 'min', 0, 'showit'});
    handles.withinframethresholdtext = uicontrol(handles.detectpanel,'Style', 'Text', 'String', 'Alignment error tolerance',...
        'Position',[0.55 0.55 0.23 0.12]);
    handles.withinframethresholdbox = uicontrol(handles.detectpanel, 'Style', 'Edit', 'String', num2str(20), ...
        'Position',[0.55 0.40 0.22 0.15],'Callback',{@setvalue, 'min', 0, 'max', 'max(originalsizex, originalsizey)'});
    handles.speedthresholdtext = uicontrol(handles.detectpanel,'Style', 'Text', 'String', 'Speed threshold',...
        'Position',[0.77 0.55 0.23 0.07]);
    handles.speedthresholdbox = uicontrol(handles.detectpanel, 'Style', 'Edit', 'String', num2str(50), ...
        'Position',[0.77 0.40 0.23 0.15],'Callback',{@setvalue, 'min', 0, 'max', max(originalsizex, originalsizey)});
    handles.setpixelthreshold = uicontrol(handles.detectpanel, 'Style', 'Pushbutton', 'String', 'Pixels -> thresholds',...
        'Position',[0.00 0.18 0.30 0.17],'Callback',@setpixelthreshold);
    handles.sethistogramthreshold = uicontrol(handles.detectpanel, 'Style', 'Pushbutton', 'String', 'Histograms -> thresholds',...
        'Position',[0.00 0.00 0.30 0.17],'Callback',@sethistogramthreshold);
    handles.detectheuristic = uicontrol(handles.detectpanel,'Style','Pushbutton','String','Heuristic tracking',...
        'Position',[0.70 0.10 0.30 0.25],'Callback',@detectheuristic);
    handles.detectmanual = uicontrol(handles.detectpanel,'Style','Pushbutton','String','Track manually',...
        'Position',[0.70 0.00 0.30 0.10],'Callback',@detectmanual);
    handles.detectold = uicontrol(handles.detectpanel,'Style','Pushbutton','String','Multi',...
        'Position',[0.30 0.00 0.20 0.35],'Callback',@detectold);
    handles.detectsingle = uicontrol(handles.detectpanel,'Style','Pushbutton','String','Single',...
        'Position',[0.50 0.00 0.20 0.35],'Callback',@detectsingle);
    
    % File Preview panel
    handles.filepreviewpanel = uipanel(handles.fig,'Title','File preview','Units','Normalized',...
        'DefaultUicontrolUnits','Normalized',...
        'Position',[0.3 0 0.4 0.95],'Visible','off');
    handles.fimg = axes('Parent',handles.filepreviewpanel,'Visible','off',...
        'Position',[0 0.15 1 0.8]);
    handles.fcap = uicontrol(handles.filepreviewpanel,'Style','Text',...
        'Position',[0.05 0 0.9 0.1]);
    
    %Debug panel
    handles.debugtools = uipanel(handles.fig, 'Title', 'Debugging tools', 'Units', 'Normalized',...
        'DefaultUicontrolUnits','Normalized',...
        'Position',[0.3 0.95 0.4 0.05],'Visible','on');
    uicontrol(handles.debugtools,'String','Enable everything','Callback',@enableeverything,'units','normalized','position',[0.0 0.05 0.3 0.9]);
    uicontrol(handles.debugtools,'String','Detect reversals', 'Callback', @detectreversals, 'units', 'normalized', 'position',[0.3 0.05 0.25 0.9]);
    uicontrol(handles.debugtools,'String','D', 'Callback', @debuggingfunction, 'units', 'normalized', 'position',[0.55 0.05 0.05 0.9]);
    handles.behaviourpopup = uicontrol(handles.debugtools,'Style', 'Popupmenu', 'String', {'Unknown behaviour', 'Stationary', 'Forwards movement', 'Backwards movement', 'Invalid behaviour', 'Bad frame', '1', '2', '3'}, 'units', 'normalized', 'position',[0.6 0.05 0.3 0.9]);
    handles.setbehaviour = uicontrol(handles.debugtools,'String', 'Set', 'Callback', @setbehaviour, 'units', 'normalized', 'position',[0.9 0.05 0.1 0.9]);
    
    % Preview panel
    handles.previewpanel = uipanel(handles.fig,'Title','Visualisation','Units','Normalized',...
        'DefaultUicontrolUnits','Normalized',...
        'Position',[0.30 0.00 0.40 0.95]);
    handles.img = axes('Parent',handles.previewpanel,'Visible','on',...
        'Position',[0.00 0.13 1.00 0.87]);
    handles.caption = uicontrol(handles.previewpanel,'Style','Text',...
        'Position',[0.20 0.06 0.57 0.05]);
    handles.showneurons = uicontrol(handles.previewpanel,'Style','Checkbox','String','Show identities',...
        'Position',[0.01 0.08 0.19 0.05],'Value',1,'Callback',@showframe);
    handles.channel = uicontrol(handles.previewpanel,'Style','popupmenu','String',{'Original','Split','Splitregions','Left','Right','Leftregions','Rightregions', 'Ratio'},...
        'Position',[0.01 0.04 0.19 0.05],'Callback',@showframe,'Value',1);
    handles.maxproject = uicontrol(handles.previewpanel, 'Style', 'Checkbox', 'String', 'Maximum projection',...
        'Position',[0.20 0.04 0.20 0.05],'Callback',@checkz, 'Visible', 'off');
    handles.showarb = uicontrol(handles.previewpanel, 'Style', 'Checkbox', 'String', 'Show arb',...
        'Position',[0.60 0.04 0.20 0.05],'Visible', 'off', 'Value', 0, 'Callback', @showframe);
    handles.frame = uicontrol(handles.previewpanel,'Style','Slider',...
        'Position',[0.04 0 0.81 0.05],'Callback',@showframe);
    handles.setframetext = uicontrol(handles.previewpanel,'Style','Text','String','Frame',...
        'Position',[0.80 0.10 0.19 0.02]);
    handles.setframe = uicontrol(handles.previewpanel,'Style','Edit','String',frame,...
        'Position',[0.80 0.06 0.10 0.04],'Callback',@setframe);
    handles.nftext = uicontrol(handles.previewpanel,'Style','Text','String','----',...
        'Position',[0.90 0.07 0.10 0.02]);
    handles.minusfifty = uicontrol(handles.previewpanel, 'Style', 'Pushbutton','String','-',...
        'Position',[0.00 0 0.04 0.05],'Callback',@minusfifty);
    handles.plusfifty = uicontrol(handles.previewpanel, 'Style', 'Pushbutton','String','+',...
        'Position',[0.85 0 0.04 0.05],'Callback',@plusfifty);
    handles.zpos = uicontrol(handles.previewpanel,'Style','Slider',...
        'Position',[0.00 0 0.10 0.05],'Callback',{@setz, 'zpos'});
    handles.setz = uicontrol(handles.previewpanel,'Style','Edit',...
        'Position',[0.10 0 0.10 0.05],'Callback',{@setz, 'setz'});
    handles.makefigure = uicontrol(handles.previewpanel,'Style','PushButton','String','Figure',...
        'Position',[0.9 0 0.1 0.05],'Callback',@makefigure);
    
    % Region panel
    handles.regionpanel = uibuttongroup(handles.fig,'Title','Region adjustment',...
        'DefaultUicontrolUnits','Normalized','Units','Normalized',...
        'Position',[0.70 0.38 0.30 0.31]);
    handles.equalizeradii = uicontrol(handles.regionpanel, 'Style', 'Pushbutton', 'String', 'Equalize radii within frames',...
        'Position',[0.57 0.88 0.41 0.12], 'Callback', @equalizeradii);
    handles.measureonlythis = uicontrol(handles.regionpanel, 'Style', 'Pushbutton', 'String', 'Measure only this region',...
        'Position',[0.57 0.75 0.41 0.12], 'Callback', @measureonlythis);
    handles.applypresettext = uicontrol(handles.regionpanel,'Style','Text','String','Apply changes to',...
        'Position',[0.00 0.85 0.51 0.10]);
    handles.applypreset = uicontrol(handles.regionpanel,'Style','popupmenu','String',{'Before current','Current frame','After current','All frames', 'Every region everywhere', 'Manual'},...
        'Position',[0.00 0.82 0.51 0.05], 'Value', 4, 'Callback', @switchapplypreset);
    handles.applyfromtext = uicontrol(handles.regionpanel,'Style','Text','String','from frame',...
        'Position',[0.00 0.68 0.24 0.07]);
    handles.applyfrom = uicontrol(handles.regionpanel,'Style','Edit','String','0',...
        'Position',[0.00 0.55 0.24 0.14],'Callback',@adjustapplyfrom);
    handles.applytotext = uicontrol(handles.regionpanel,'Style','Text','String','to frame',...
        'Position',[0.26 0.68 0.24 0.07]);
    handles.applyto = uicontrol(handles.regionpanel,'Style','Edit','String','0',...
        'Position',[0.26 0.55 0.24 0.14],'Callback',@adjustapplyto);
    handles.selectregion = uicontrol(handles.regionpanel,'Style','Pushbutton',...
        'String','Select',...
        'Position',[0.00 0.25 0.25 0.25],'Callback',@selectregion);
    handles.findnextregion = uicontrol(handles.regionpanel,'Style','Pushbutton',...
        'String','Find next unnamed',...
        'Position',[0.26 0.25 0.25 0.25],'Callback',@findnextregion);
    handles.measureregion = uicontrol(handles.regionpanel,'Style','Checkbox','String','Measure',...
        'Position',[0.81 0.50 0.19 0.07], 'Value', 0, 'Callback', @setmeasureregion);
    handles.addregion = uicontrol(handles.regionpanel,'Style','Pushbutton','String','+region',...
        'Position',[0.00 0.115 0.17 0.11],'Callback',@addregion);
    handles.addarb = uicontrol(handles.regionpanel,'Style','Pushbutton','String','+arb',...
        'Position',[0.00 0.00 0.17 0.11],'Callback',@addarb);
    handles.copyregion = uicontrol(handles.regionpanel,'Style','Pushbutton','String','Copy',...
        'Position',[0.17 0.00 0.17 0.225],'Callback',@copyregion);
    handles.deleteregion = uicontrol(handles.regionpanel,'Style','Pushbutton','String','Delete',...
        'Position',[0.34 0.00 0.17 0.225],'Callback',@deleteregion);
    handles.regionnametext = uicontrol(handles.regionpanel,'Style','Text','String','Region name (0)',...
        'Position',[0.55 0.66 0.22 0.06]);
    handles.regionnamedisplay = uicontrol(handles.regionpanel,'Style','Edit','String',selectedname,...
        'Position',[0.55 0.52 0.22 0.14],'Enable', 'off','Callback',@setregionname);
    handles.adjustleft = uicontrol(handles.regionpanel,'Style','Pushbutton',...
        'String','Left (0;0)',...
        'Position',[0.55 0.35 0.22 0.15],'Callback',@adjustleft);
    handles.adjustright = uicontrol(handles.regionpanel,'Style','Pushbutton',...
        'String','Right (0;0)',...
        'Position',[0.78 0.35 0.22 0.15],'Callback',@adjustright);
    handles.displaceboth = uicontrol(handles.regionpanel,'Style','Pushbutton',...
        'String','Displace',...
        'Position',[0.55 0.25 0.22 0.10],'Callback',@displaceboth);
    handles.adjustarb = uicontrol(handles.regionpanel,'Style','Pushbutton',...
        'String','Adj arb',...
        'Position',[0.78 0.25 0.22 0.10],'Callback',@adjustarb);
    handles.leftradiustext = uicontrol(handles.regionpanel,'Style','Text','String','Left radius',...
        'Position',[0.55 0.15 0.22 0.07]);
    handles.leftradiusdisplay = uicontrol(handles.regionpanel,'Style','Edit','String',selectedradiusy,...
        'Position',[0.55 0.01 0.22 0.14],'Callback',@adjustleftradius);
    handles.rightradiustext = uicontrol(handles.regionpanel,'Style','Text','String','Right radius',...
        'Position',[0.78 0.15 0.22 0.07]);
    handles.rightradiusdisplay = uicontrol(handles.regionpanel,'Style','Edit','String',selectedradiusc,...
        'Position',[0.78 0.01 0.22 0.14],'Callback',@adjustrightradius);
    
    %Measurement panel
    handles.measurementpanel = uipanel('Parent',handles.fig,'Title','Measurement settings','Units','Normalized',...
        'DefaultUicontrolUnits','Normalized','Visible','on',...
        'Position',[0.70 0.15 0.30 0.22]);
    handles.radiustext = uicontrol(handles.measurementpanel,'Style','Text','String','Radius multiplier',...
        'Position',[0.41 0.21 0.18 0.15]);
    handles.radiusmultiplier = uicontrol(handles.measurementpanel,'Style','Edit','String',num2str(radius),...
        'Position',[0.41 0.01 0.18 0.20],'Callback',@setradius);
    handles.radiusmultiplierminus = uicontrol(handles.measurementpanel, 'Style', 'Pushbutton', 'String', '-',...
        'Position',[0.35 0.03 0.06 0.14],'Callback',{@setradius, -1});
    handles.radiusmultiplierplus = uicontrol(handles.measurementpanel, 'Style', 'Pushbutton', 'String', '+',...
        'Position',[0.59 0.03 0.06 0.14],'Callback',{@setradius, 1});
    handles.backgroundtext = uicontrol(handles.measurementpanel,'Style','Text','String','Background',...
        'Position',[0.71 0.55 0.19 0.10]);
    handles.backgroundpopup = uicontrol(handles.measurementpanel, 'Style', 'Popupmenu', 'String', {'Lowest percentile', 'Channel median', 'Camera offset', 'No background subtraction'},...
        'Position',[0.60 0.52 0.39 0.05],'Value', 1, 'Callback', @switchbackground);
    handles.localbackground = uicontrol(handles.measurementpanel, 'Style', 'Checkbox', 'String', 'Local background', ...
        'Position',[0.60 0.33 0.39 0.10], 'Value', 1, 'Callback', @switchbackground);
    handles.percentiletext = uicontrol(handles.measurementpanel,'Style','Text','String','Percentile',...
        'Position',[0.70 0.21 0.19 0.10]);
    handles.percentile = uicontrol(handles.measurementpanel,'Style','Edit','String',num2str(percentile),...
        'Position',[0.70 0.01 0.19 0.20],'Callback',@setpercentile);
    handles.offsettext = uicontrol(handles.measurementpanel,'Style','Text','String','Offset',...
        'Position',[0.70 0.21 0.19 0.10], 'Visible', 'off');
    handles.offset = uicontrol(handles.measurementpanel,'Style','Edit','String',num2str(offset),...
        'Position',[0.70 0.01 0.19 0.20],'Callback',{@setvalue, 'min', 0, 'setglobal', 'offset'}, 'Visible', 'off');
    handles.foregroundtext = uicontrol(handles.measurementpanel,'Style','Text','String','Foreground',...
        'Position',[0.11 0.575 0.19 0.10]);
    handles.foregroundpopup = uicontrol(handles.measurementpanel, 'Style', 'Popupmenu', 'String', {'Fixed max number of pixels', 'Fixed proportion of pixels', 'All pixels in the regions'}, ...
        'Position',[0.01 0.52 0.39 0.05], 'Value', 1, 'Callback', @switchforeground);
    handles.setmedianoffset = uicontrol(handles.measurementpanel, 'Style', 'Pushbutton', 'String', 'Set median as offset',...
        'Position',[0.41 0.40 0.18 0.30],'Callback',@setmedianoffset);
    handles.excludeoverlap = uicontrol(handles.measurementpanel, 'Style', 'Checkbox', 'String', 'Exclude overlapping', ...
        'Position',[0.01 0.33 0.39 0.10], 'Value', 1);
    handles.pixelnumbertext = uicontrol(handles.measurementpanel,'Style','Text','String','Using',...
        'Position',[0.11 0.21 0.19 0.10]);
    handles.pixelnumber = uicontrol(handles.measurementpanel,'Style','Edit','String',num2str(pixelnumber),...
        'Position',[0.11 0.01 0.19 0.20],'Callback',@setpixelnumber);
    
    %channel chooser
    handles.channelchooser = uicontrol(handles.measurementpanel, 'Style', 'Popupmenu', 'String', {'YFP left, CFP right', 'CFP left, YFP right'}, 'Value', 2, ... %'Single channel'
        'Position', [0.01 0.80 0.32 0.20],'Callback',@updatechannelchooser);
    handles.correctionfactorAtext = uicontrol(handles.measurementpanel, 'Style', 'Text', 'String', 'A=', 'HorizontalAlignment', 'right',...
        'Position', [0.01 0.72 0.05 0.10]);
    handles.correctionfactorA = uicontrol(handles.measurementpanel, 'Style', 'Edit', 'String', correctionfactorA,...
        'Position', [0.07 0.72 0.10 0.12],'Callback',{@setvalue, 'setglobal', 'correctionfactorA'});
    handles.correctionfactorBtext = uicontrol(handles.measurementpanel, 'Style', 'Text', 'String', 'B=', 'HorizontalAlignment', 'right',...
        'Position', [0.17 0.72 0.05 0.10]);
    handles.correctionfactorB = uicontrol(handles.measurementpanel, 'Style', 'Edit', 'String', correctionfactorB,...
        'Position', [0.23 0.72 0.10 0.12],'Callback',{@setvalue, 'setglobal', 'correctionfactorB'});
    
    %Results panel
    handles.resultspanel = uipanel(handles.fig,'Title','Final results',...
        'DefaultUicontrolUnits','Normalized','Units','Normalized',...
        'Position',[0.70 0.00 0.30 0.14]);
    handles.calculate = uicontrol(handles.resultspanel,'Style','Pushbutton',...
        'String','Calculate results',...
        'Position',[0.00 0.00 0.40 1.00],'Callback',@calculateratios);
    
    handles.plotratios = uicontrol(handles.resultspanel,'Style','Pushbutton','String','Plot ratios',...
        'Position',[0.41 0.46 0.39 0.54], 'Callback',@plotratios);
    handles.movingaveragetext = uicontrol(handles.resultspanel,'Style','Text','String','Moving average',...
        'Position',[0.81 0.75 0.19 0.25]);
    handles.movingaveragebox = uicontrol(handles.resultspanel,'Style','Edit','String',num2str(movingaverage),...
        'Position',[0.81 0.50 0.19 0.25], 'Callback',{@setvalue, 'round', 1, 'min', 1, 'max', 'nf'});
    handles.plotposition = uicontrol(handles.resultspanel,'Style','Pushbutton','String','Position',...
        'position',[0.41 0.00 0.19 0.45], 'Callback',@plotposition);
    handles.plotchannels = uicontrol(handles.resultspanel,'Style','Pushbutton','String','Intensities',...
        'Position',[0.61 0.00 0.19 0.45], 'Callback',@plotchannels);
    handles.plottogether = uicontrol(handles.resultspanel,'Style','Pushbutton','String','Everything',...
        'Position',[0.81 0.00 0.19 0.45], 'Callback',@plottogether);
    
    
    %Cells for saving and loading data
    trytoload = {'leftthreshold', 'rightthreshold', 'rightdisplacementx', 'rightdisplacementy',...
                'originalsizex', 'originalsizey', 'pixelnumber', 'percentile', 'offset', 'minimalneuronsize',...
                'correctionsearchradius', 'alignmentsearchradius', 'radius', 'maxnumberofregions', 'numberofregionsfound',...
                'ratios', 'leftvalues', 'rightvalues', 'leftbackground', 'rightbackground',...
                'rationames', 'rightregionx', 'rightregiony', 'rightregionz', 'leftregionx', 'leftregiony', 'leftregionz', 'regionimportant', ...
                'regionname', 'leftregionradius', 'rightregionradius', 'numberofregions', 'cropleft', 'cropright', 'croptop', 'cropbottom',...
                'leftwidth', 'unusablerightx', 'subchannelsizex', 'subchannelsizey', 'gaussianx', 'gaussiany', 'gaussians', 'behaviour', 'usingbehaviour',...
                'frametime', 'framex', 'framey', 'correctionfactorA', 'correctionfactorB', 'detectedframes', 'detectedneurons', 'arbarea', 'excludedarea'};
    trytosetstring = {'withinframethresholdbox', 'speedthresholdbox', 'leftthresholdbox', 'rightthresholdbox', 'radiusmultiplier', 'pixelnumber', 'percentile',...
                'offset', 'alignmentsearchradius', 'correctionsearchradius', 'minimalneuronsize', 'movingaveragebox', 'correctionfactorA', 'correctionfactorB'};
    trytosetvalue = {'foregroundpopup','backgroundpopup', 'excludeoverlap','showneurons', 'channel', 'channelchooser', 'behaviourpopup'};


    % Control groups
    controlsetfile = [handles.folder handles.updatefiles handles.browse handles.rotatestack handles.files];
    controlbrowsemovie  = [handles.frame handles.setframe handles.setframetext handles.nftext handles.plusfifty handles.minusfifty handles.makefigure]; %handles.play 
    controlsetchannel = [handles.channel handles.channelchooser handles.correctionfactorA handles.correctionfactorAtext handles.correctionfactorB handles.correctionfactorBtext];
    controlshowneurons = [handles.showneurons];
    controlcalculate = [handles.calculate];
    controlmanipulate = [handles.exportdataaslog handles.exportdataastxt];
    controlplot = [handles.plotratios handles.plotchannels handles.plottogether handles.plotposition handles.movingaveragebox handles.movingaveragetext];
    controlsetalignment = [handles.loadanalysis handles.saveanalysis handles.alignmentsearchradius handles.alignmentsearchradiusdisplay handles.setalignment handles.alignmentx handles.alignmenty handles.alignmentdisplaytext1 handles.alignmentdisplaytext2 handles.alignmentdisplaytextx handles.alignmentdisplaytexty handles.subchannelsizedisplay handles.subchannelsizedisplaytexttop handles.subchannelsizedisplaytextbottom];
    controldetect = [handles.detectheuristic handles.detectmanual handles.detectold handles.detectsingle handles.filtertext handles.filter handles.leftthresholdbox handles.leftthresholdtext handles.rightthresholdbox handles.rightthresholdtext handles.setpixelthreshold handles.sethistogramthreshold handles.withinframethresholdbox handles.withinframethresholdtext handles.speedthresholdbox handles.speedthresholdtext handles.correctionsearchradius handles.correctionsearchradiustext handles.minimalneuronsize handles.minimalneuronsizetext handles.excludedarea handles.saturationcheck handles.mediancheck];
    controlselectregion = [handles.selectregion handles.findnextregion];
    controladjustregion = [handles.applypreset handles.applypresettext handles.addregion handles.addarb handles.copyregion handles.deleteregion handles.adjustleft handles.adjustright handles.displaceboth handles.adjustarb handles.leftradiusdisplay handles.leftradiustext handles.rightradiusdisplay handles.rightradiustext handles.regionnamedisplay handles.regionnametext handles.measureregion handles.equalizeradii handles.measureonlythis]; %handles.leftpositiondisplay handles.rightpositiondisplay handles.regiondisplay
    controlapplymanual = [handles.applyfrom handles.applyto handles.applyfromtext handles.applytotext];
    controladjustmeasurement = [handles.radiusmultiplier handles.radiustext handles.radiusmultiplierminus handles.radiusmultiplierplus handles.foregroundpopup handles.foregroundtext handles.excludeoverlap handles.localbackground handles.pixelnumber handles.pixelnumbertext handles.backgroundpopup handles.backgroundtext handles.percentile handles.percentiletext handles.offset handles.offsettext handles.setmedianoffset];
    controlcrop = [handles.cropleft handles.croplefttext handles.cropright handles.croprighttext handles.croptop handles.croptoptext handles.cropbottom handles.cropbottomtext handles.cropmiddletext handles.croplmiddle handles.croprmiddle handles.setcropmiddle handles.setcropall];
    controlzstack = [handles.maxproject];
    controlz = [handles.zpos handles.setz];
    
    cansetfile = true;
    canbrowsemovie = false;
    cansetchannel = false;
    canshowneurons = false;
    cancalculate = false;
    canplot = false;
    canmanipulate = false;
    cansetalignment = false;
    candetect = false;
    canselectregion = false;
    canadjustregion = false;
%    canapplymanual = false;
    canadjustmeasurement = false;
    cancrop = false;
    
    % Startup
    set(0,'DefaultAxesLineStyleOrder',{'-',':','--','-.'}); %When plotting results, cycle through different line styles in addition to the different colours so that there is more combinations possible
    
    initialize;
    loadsettings;
    
    updatefilelist(handles.fig,[]);
    set(handles.fig,'Visible','on');
    set([controlzstack controlz], 'Visible', 'off');
    
    updatevisibility;
    
    function initialize
        
        warning('off', 'MATLAB:imagesci:tiffmexutils:libtiffErrorAsWarning'); %don't worry about tiff warnings
        
        try
            bioformatsavailable = false;
            locitoolsavailable = false;
            classpath = javaclasspath;
            for i=1:numel(classpath)
                if strfind(classpath{i}, 'bioformats_package.jar') == numel(classpath{i}) - numel('bioformats_package.jar') + 1; %if one of the paths is a direct link to a bioformats_package.jar
                    if exist(classpath{i}, 'file') == 2 %see if it actually exists
                        bioformatsavailable = true; %if it does exist, then we found it,
                    else
                        javarmpath(classpath{i}); %if it doesn't actually exist, then it should be removed from the java path
                    end
                end
                if strfind(classpath{i}, 'loci_tools.jar') == numel(classpath{i}) - numel('loci_tools.jar') + 1; %if one of the paths is a direct link to a loci_tools.jar
                    if exist(classpath{i}, 'file') == 2 %see if it actually exists
                        locitoolsavailable = true; %if it does exist, then we found it,
                    else
                        javarmpath(classpath{i}); %if it doesn't actually exist, then it should be removed from the java path
                    end
                end
            end
            pathsline = path;
            separator = pathsep;
            whereseparated = [0, strfind(pathsline, separator), numel(pathsline)+1];
            paths = [];
            for i=1:numel(whereseparated)-1
                paths{i} = pathsline(whereseparated(i)+1:whereseparated(i+1)-1); %#ok<AGROW>
            end
            for i=1:numel(paths)
                if bioformatsavailable && locitoolsavailable
                    break
                end
                currentfullfile = fullfile(paths{i}, 'bioformats_package.jar'); %add the filename to the path
                if exist(currentfullfile, 'file') == 2 %and check if bioformats_package.jar exists there
                    javaaddpath(currentfullfile); %if it does exist, then we found it,
                    bioformatsavailable = true;
                end
                currentfullfile = fullfile(paths{i}, 'loci_tools.jar'); %add the filename to the path
                if exist(currentfullfile, 'file') == 2 %and check if loci_tools.jar exists there
                    javaaddpath(currentfullfile); %if it does exist, then we found it,
                    locitoolsavailable = true;
                end
            end
        catch, err = lasterror; %#ok<CTCH,LERR> %if some error occurred while fiddling with the file, then just don't use it
            fprintf(2, 'Warning: there was an unexpected error while trying to locate the bioformats_package.jar or loci_tools.jar file.\n');
            fprintf(2, '%s\n', err.message);
        end
    end
    
    function updatefilelist(hobj,eventdata)
        currentpath = get(handles.folder,'String');
        
        foundxml = false;
        files = {};
        
        checkingtifffiles = [dir(fullfile(currentpath, '*.tiff')), dir(fullfile(currentpath, '*.tif'))];
        checkingallfiles = dir(fullfile(currentpath, '*.*'));
        checkingallfiles = checkingallfiles(~cellfun(@(a) numel(a) >= 4 && strcmpi(a(end-3:end), '.txt'), {checkingallfiles.name})); %excluding txt files
        if numel(checkingtifffiles) > 0 && numel(checkingallfiles)-2 == numel(checkingtifffiles) && all(strcmp({checkingallfiles(3:end).name}, {checkingtifffiles.name}))
            files{1} = checkingtifffiles(1).name;
            foundxml = true;
            fileformat = CONST_FILEFORMAT_SINGLETIFF;
        end
        
        for i=1:numel(readableextensions)
            if i >= 4 && foundxml %don't show tif files when we've already found an xml (because xml suggests that it's a prairie directory with single-image tiffs
                break;
            end
            currentfiles = dir(fullfile(currentpath, readableextensions{i}));
            currentfilenames = {currentfiles.name};
            if ~isempty(currentfilenames)
                files(end+1:end+numel(currentfilenames)) = currentfilenames;
            end
            if i == 1 && ~isempty(files)
                foundxml = true;
            end
        end
        
        %movies that are simply channel 2 of a single movie separated into two files according to channels will be hidden so that only channel 1 shows up in the filelist
        shouldbehidden = [];
        for i=1:numel(files)
            dots = strfind(files{i}, '.');
            if numel(dots) >= 2
                if strcmpi(files{i}(dots(end-1)+1:dots(end)-1), 'ch2')
                    matchingwouldbe = files{i};
                    matchingwouldbe(dots(end)-1) = '1';
                    if any(cellfun(@(x) (strcmp(x, matchingwouldbe)), files))
                        shouldbehidden(end+1) = i; %#ok<AGROW>
                    end
                end
            end
        end
        files(shouldbehidden) = [];
        
        if isempty(files)
            set(handles.files,'String','');
            set(handles.files,'Enable','off');
            set(handles.load,'Enable','off');
            set(handles.filepreviewpanel,'Visible','on');
            set(handles.previewpanel,'Visible','off');
            cla(handles.fimg);
            set(handles.fcap,'String','No readable files found');
        else
            set(handles.files,'String',files);
            set(handles.files,'Value',1);
            set(handles.files,'Enable','on');
            selectfile(hobj,eventdata);
        end
    end
    
    % Select a new data path graphically
    function browse(hobj,eventdata)
        newpath = uigetdir(currentpath,'Select data folder');
        if newpath ~= 0
            currentpath = newpath;
            set(handles.folder,'String',currentpath);
            updatefilelist(hobj,eventdata);
        end
    end
    
    % Show preview information when selecting a file in the list
    function selectfile(hobj, eventdata) %#ok<INUSD>
        bfreader = [];
        newfile = files{get(handles.files, 'Value')};
        f = []; %image frame
        if numel(newfile) >= 3
            if strcmpi(newfile(end-2:end), 'xml')
                fileformat = CONST_FILEFORMAT_XML;
                %quickly parsing the xml assuming it is from PrairieView
                %just obtaining the first frame as soon as posssible
                %detailed parsing will happen during the loading phase (loadstack function)
                %{
                xmlserver = xmlread(fullfile(currentpath,newfile));
                pvscanindex = findnode(xmlserver, 'PVScan', true);
                sequenceindices = findnode(xmlserver.item(pvscanindex), 'Sequence', false);
                frameindices = findnode(xmlserver.item(pvscanindex).item(sequenceindices(1)), 'Frame', false);
                fileindex = findnode(xmlserver.item(pvscanindex).item(sequenceindices(1)).item(frameindices(1)), 'File');
                ffilename = char(getattribute(xmlserver.item(pvscanindex).item(sequenceindices(1)).item(frameindices(1)).item(fileindex), 'filename'));
                f = imread(fullfile(currentpath, ffilename));
                %}
                f = 0;
                nf = NaN;
            else
                fileformat = CONST_FILEFORMAT_BIOFORMATS;
                bfreader = bfGetReader(fullfile(currentpath, newfile));
                f = bfGetPlane(bfreader, 1);
                nf = bfreader.getImageCount();
                if bfreader.getChannelDimLengths == 2
                    nf = floor(nf/2);
                end
            end
        end
        if ~isempty(f)
            imshow(f, [], 'Parent', handles.fimg);
            if ~isnan(nf)
                set(handles.fcap,'String', sprintf('%ux%u, %u frames', size(f, 2), size(f, 1), nf));
            else
                set(handles.fcap,'String', sprintf('%ux%u', size(f, 2), size(f, 1)));
            end
        else
            fprintf('File could not be read successfully.\n');
        end
        set(handles.load, 'Enable', 'on');
        set(handles.filepreviewpanel,'Visible','on');
        set(handles.previewpanel,'Visible','off');
    end

    function setexcludedarea(hobj, eventdata)
        
        excludedarea = false(subchannelsizey, subchannelsizex);
        
        if correctionsearchradius == 0 || isnan(correctionsearchradius)
            questdlg('The radius of the paintbrush used to specify areas to exclude is determined by the peak correction radius. It needs to be set to a value larger than 0.','Tracking area exclusion','Ok','Ok')
            updatevisibility;
            showframe(hobj,eventdata);
            return
        else
            previouschannelvalue = get(handles.channel, 'Value');
            if leftthreshold >= rightthreshold
                tousechannel = 4;
            else
                tousechannel = 5;
            end
            set(handles.channel, 'Value', tousechannel);
            showframe(hobj, eventdata);

            clicktype = 'nothing yet';
            while ~strcmpi(clicktype, 'alt')
                [x, y, clicktype] = zinput('circle', 'xradius', correctionsearchradius, 'yradius', correctionsearchradius);
                if ~strcmpi(clicktype, 'alt')
                    excludedarea(withinrange(subchannelsizey, subchannelsizex, x, y, correctionsearchradius)) = true;
                    hold(handles.img, 'on');
                    fill(ceil(correctionsearchradius)*circlepointsx+x, ceil(correctionsearchradius)*circlepointsy+y, [1 1 1], 'Parent', handles.img, 'EdgeColor', 'none');
                end
            end

            set(handles.channel, 'Value', previouschannelvalue);
            showframe(hobj, eventdata)
        end
    end

    function returnstring = betweennextquotes (inputstring, afterthispattern)
        whereafter = strfind(inputstring, afterthispattern);
        if isempty(whereafter)
            returnstring = '';
            return
        end
        whereafter = whereafter(end);
        nextquotes = whereafter + strfind(inputstring(whereafter+1:end), '"');
        returnstring = inputstring(nextquotes(1)+1:nextquotes(2)-1);
    end
    
    function croppedleft = cropleftdata (imagedata)
        croppedleft = imagedata(max(-rightdisplacementy,1)+croptop:max(-rightdisplacementy,1)+croptop+subchannelsizey-1, max(unusablerightx,1)+cropleft:max(unusablerightx,1)+cropleft+subchannelsizex-1);
    end
    
    function croppedright = croprightdata (imagedata)
        croppedright = imagedata(max(rightdisplacementy,1)+croptop:max(rightdisplacementy,1)+croptop+subchannelsizey-1, rightdisplacementx+unusablerightx+cropleft:rightdisplacementx+unusablerightx+cropleft+subchannelsizex-1);
    end

    function croppedmiddleleft = cropmiddleleftdata (imagedata)
        croppedmiddleleft = imagedata(max(-rightdisplacementy,1)+croptop:max(-rightdisplacementy,1)+croptop+subchannelsizey-1, max(-(rightdisplacementx-originalsizex/2),1)+cropleft:max(-(rightdisplacementx-originalsizex/2),1)+cropleft+subchannelsizex-1);
    end

    function croppedmiddleright = cropmiddlerightdata (imagedata)
        croppedmiddleright = imagedata(max(rightdisplacementy,1)+croptop:max(rightdisplacementy,1)+croptop+subchannelsizey-1, max(rightdisplacementx-originalsizex/2,1)+cropleft:max(rightdisplacementx-originalsizex/2,1)+cropleft+subchannelsizex-1);
    end

    function framedata = readframe (whichframe, whichchannel, whichz, xcoor, ycoor, xsize, ysize)
        
        if exist('whichchannel', 'var') ~= 1 || isempty(whichchannel)
            whichchannel = 1;
        end
        if stack3d && (exist('whichz', 'var') ~= 1 || isempty(whichz))
            whichz = str2double(get(handles.setz, 'String'));
        end
        
        framedata = [];
        
        if stack3d
            if maxproject
                if whichchannel == 1
                    framestoproject = find(tindex1 == whichframe);
                else
                    framestoproject = find(tindex2 == whichframe);
                end
                if stacktucam
                    tempzstack = NaN(numel(framestoproject), originalsizey, originalsizex/2);
                else
                    tempzstack = NaN(numel(framestoproject), originalsizey, originalsizex);
                end
                for j=1:numel(framestoproject)
                    if whichchannel == 1
                        if ~isempty(xmlstruct)
                            tempzstack(j, :, :) = imread(fullfile(currentpath, xmlstruct.frame(framestoproject(j)).filename));
                        end
                    end
                end
                framedata = squeeze(max(tempzstack, [], 1));
            else %getting a single z plane
                if whichchannel == 1
                    framestochoosefrom = find(tindex1 == whichframe);
                else
                    framestochoosefrom = find(tindex2 == whichframe);
                end
                correctslice = framestochoosefrom(abs(zpos1(framestochoosefrom) - whichz)<0.01); %absolute difference of less than epsilon as a way to calculate equivalence between floating-point numbers
                if whichchannel == 1
                    if ~isempty(xmlstruct)
                        framedata = imread(fullfile(currentpath, xmlstruct.frame(correctslice).filename));
                        framedata = squeeze(framedata);
                    end
                end
            end
        end
        if fileformat == CONST_FILEFORMAT_BIOFORMATS
            if stacktucam
                if whichchannel == 1
                    actualframetoread = whichframe*2-1;
                else
                    actualframetoread = whichframe*2;
                end
            else
                actualframetoread = whichframe;
            end
            if exist('ysize', 'var')
                framedata = bfGetPlane(bfreader, actualframetoread, xcoor, ycoor, xsize, ysize);
            else
                framedata = bfGetPlane(bfreader, actualframetoread);
            end
        elseif fileformat == CONST_FILEFORMAT_SINGLETIFF
            framedata = imread(fullfile(currentpath, xmlstruct.frame(whichframe).filename));
            framedata = squeeze(framedata);
        end
        
        if stacktucam 
            if (whichchannel == 1 && stacktucamflipx1) || (whichchannel == 2 && stacktucamflipx2)
                framedata = fliplr(framedata);
            end
            if (whichchannel == 1 && stacktucamflipy1) || (whichchannel == 2 && stacktucamflipy2)
                framedata = flipud(framedata);
            end
        end

        if ~exist('ysize', 'var') && size(framedata, 1) > size(framedata, 2)
            framedata = framedata';
        end
        
        framedata = double(framedata);
        
        if rotatestack
            framedata = rot90(framedata);
        end
        
    end

    function cachesubimages(whichframe)
        if numel(stackcache) == 1 && stackcache == 0 && ~stack3d %Only if not everything is already cached
            if leftcached ~= whichframe || rightcached ~= whichframe
                if stacktucam && ~isempty(bfreader)
                    f1 = readframe(whichframe, 1);
                    leftsubimage = cropmiddleleftdata(f1);
                    f2 = readframe(whichframe, 2);
                    rightsubimage = cropmiddlerightdata(f2);
                else
                    f = readframe(whichframe);
                    leftsubimage = cropleftdata(f);
                    rightsubimage = croprightdata(f);
                end
                leftcache = leftsubimage; %Cache left image for direct retrieval
                rightcache = rightsubimage; %Cache right image for direct retrieval
                leftcached = whichframe;
                rightcached = whichframe;
            end
        end
    end
    
    %Returns left subimage
    function L = LEFT(whichframe, dontcacheit)
        if ~(numel(stackcache) == 1 && stackcache == 0) %If everything is cached
            if stacktucam
                L(:, :) = cropmiddleleftdata(stackcache(whichframe, :, :));
            else
                L(:, :) = cropleftdata(stackcache(whichframe, :, :));
            end
        else
            if leftcached ~= whichframe || stack3d
                if stacktucam
                    f = readframe(whichframe, 1);
                    leftsubimage = cropmiddleleftdata(f);
                else
                    f = readframe(whichframe);
                    leftsubimage = cropleftdata(f);
                end
                if ~(exist('dontcacheit', 'var') == 1 && strcmpi(dontcacheit, 'no caching') == 1) %Doing this way with and && avoids attempting to access the argument if it doesn't exist
                    leftcache = leftsubimage;
                    leftcached = whichframe;
                end
                L = leftsubimage;
            else
                L = leftcache;
            end
        end
    end
    
    % Returns right subimage
    function R = RIGHT(whichframe, dontcacheit)
        if ~(numel(stackcache) == 1 && stackcache == 0) %If everything is cached
            if stacktucam
                R(:, :) = cropmiddlerightdata(stackcache(whichframe, :, :));
            else
                R(:, :) = croprightdata(stackcache(whichframe, :, :));
            end
        else
            if rightcached ~= whichframe || stack3d
                if stacktucam
                    f = readframe(whichframe, 2);
                    rightsubimage = cropmiddlerightdata(f);
                else
                    f = readframe(whichframe);
                    rightsubimage = croprightdata(f);
                end
                if ~(exist('dontcacheit', 'var') == 1 && strcmpi(dontcacheit, 'no caching') == 1) %Doing this way with and && avoids attempting to access the argument if it doesn't exist
                    rightcache = rightsubimage;
                    rightcached = whichframe;
                end
                R = rightsubimage;
            else
                R = rightcache;
            end
        end
    end

    function loadstack(hobj,eventdata) % Unloading is also handled here
        %clear calculated values
        numberofregionsfound = 0;
        maxnumberofregions = 0;
        ratios = [];
        behaviour = [];
        usingbehaviour = false;
        leftvalues = [];
        rightvalues = [];
        leftbackground = [];
        rightbackground = [];
        frametime = NaN;
        framex = NaN;
        framey = NaN;
        arbarea = [];
        
        stack3d = false;
        stacktucam = false;
        stacktucamflipx1 = false;
        stacktucamflipy1 = false;
        stacktucamflipx2 = false;
        stacktucamflipy2 = false;
        xmlstruct = [];
        uniqueposz = [];
        
        detectedframes = [];
        detectedneurons = [];
        
        dontupdatevisibility = true; %a quick fix: updatevisibility is called by many of the initializing functions, including clearallregions - this way it will only really be updated after load is finished. TODO: should be handled more properly
        
        clearallregions;
        
        set(handles.showarb, 'Visible', 'off', 'Value', 0);
        set(handles.cropleft, 'String', num2str(cropleft));
        set(handles.cropright, 'String', num2str(cropright));
        set(handles.cropbottom, 'String', num2str(cropbottom));
        set(handles.croptop, 'String', num2str(croptop));
        set(handles.croplmiddle, 'String', num2str(leftwidth));
        set(handles.croprmiddle, 'String', num2str(rightdisplacementx+unusablerightx));
        
        if strcmp(get(handles.load, 'String'), 'Load movie') % If it's a load command
            dontupdateframe = true; %showframe is called by many of the initializing functions. This way it will only really be updated after load is finished
            successfullyread = false;
            
            set(handles.load, 'String', 'Loading movie...', 'Enable', 'off');
            drawnow;
            
            if fileformat == CONST_FILEFORMAT_XML
                stringfile = fopen(fullfile(currentpath,newfile));
                xmlframes = 0;
                readline = 'nothing';
                xconversion = NaN;
                yconversion = NaN;
                currentlineindex = 0;
                while ischar(readline) || readline ~= -1
                    currentlineindex = currentlineindex+1;
                    readline = fgets(stringfile);
                    if mod(currentlineindex, 20000) == 0
                        fprintf('%d\n', currentlineindex);
                    end
                    if ~isempty(strfind(readline, '<Frame'))
                        xmlframes = xmlframes + 1;
                        xmlstruct.frame(xmlframes).time = str2double(betweennextquotes(readline, 'relativeTime'));%'absoluteTime'));
                        continue
                    end
                    currentframefilename = betweennextquotes(readline, 'filename');
                    if ~isempty(currentframefilename)
                        xmlstruct.frame(xmlframes).filename = currentframefilename;
                        continue
                    end
                    if ~isempty(strfind(readline, 'positionCurrent_XAxis'))
                        xmlstruct.frame(xmlframes).x = str2double(betweennextquotes(readline, 'value'));
                        continue
                    end
                    if ~isempty(strfind(readline, 'positionCurrent_YAxis'))
                        xmlstruct.frame(xmlframes).y = str2double(betweennextquotes(readline, 'value'));
                        continue
                    end
                    if ~isempty(strfind(readline, 'positionCurrent_ZAxis'))
                        xmlstruct.frame(xmlframes).z = str2double(betweennextquotes(readline, 'value'));
                        continue
                    end
                    if ~isempty(strfind(readline, 'micronsPerPixel_XAxis'))
                        xconversion = str2double(betweennextquotes(readline, 'value'));
                        continue
                    end
                    if ~isempty(strfind(readline, 'micronsPerPixel_YAxis'))
                        yconversion = str2double(betweennextquotes(readline, 'value'));
                        continue
                    end
                end
                fclose(stringfile);
                nf = numel(xmlstruct.frame);
                for i=1:nf
                    xmlstruct.frame(i).x = xmlstruct.frame(i).x / xconversion;
                    xmlstruct.frame(i).y = xmlstruct.frame(i).y / yconversion;
                end
                xmlstruct.xyintoz = mean([xconversion, yconversion]) / abs(xmlstruct.frame(1).z-xmlstruct.frame(2).z);
                
                [originalsizey, originalsizex] = size(imread(fullfile(currentpath, xmlstruct.frame(1).filename)));
                
                successfullyread = true;
                
                if nf >= 2 && xmlstruct.frame(1).z ~= xmlstruct.frame(2).z
                    stack3d = true;
                    zpos1 = horzcat(xmlstruct.frame.z);
                    nf1 = nf;
                end
                
            end
            
            if ~successfullyread
                if fileformat == CONST_FILEFORMAT_BIOFORMATS
                    nf = bfreader.getImageCount();
                    [originalsizey, originalsizex] = size(bfGetPlane(bfreader, 1));
                    if bfreader.getChannelDimLengths == 2
                        nf = floor(nf / 2);
                        originalsizex = originalsizex * 2;
                        stacktucam = true;
                        fprintf('It appears to be a dual-cam stack bioformats file.\n');
                    end
                    speedreadable = true;
                    fprintf('File %s successfully read using bioformats.\n', fullfile(currentpath,newfile));
                else
                    fprintf(2, 'Warning: did not understand the file format.\n');
                end
            end
            
            
            if stack3d
                
                %making sure that it also works for bidirectional scans
                uniqueposz = unique(zpos1);
                uniqueposz = sort(uniqueposz);
                uniqueposn = zeros(1, numel(uniqueposz));
                
                tindex1 = NaN(1, nf1);
                frameindex = 0;
                while frameindex < nf1
                    frameindex = frameindex + 1;
                    whichz = find(uniqueposz==zpos1(frameindex));
                    uniqueposn(whichz) = uniqueposn(whichz) + 1;
                    tindex1(frameindex) = max(uniqueposn);
                end
                
                nf = max(tindex1);
                
                %if the last t-frame contains less than normal number of frames from each of the two files (because the movie was stopped at a weird time/place), don't look at the last t-frame
                if sum(tindex1 == nf) < sum(tindex1 == 1)
                    fprintf('The last z-stack in the t-series appears to be shorter than expected. Ignoring it...\n');
                    nf = nf - 1;
                end
                
                checkz;
                
            else
                
                set(controlzstack, 'Visible', 'off');
                set(controlz, 'visible', 'off');
                set(handles.minusfifty, 'Position',[0.00 0 0.04 0.05]);
                set(handles.frame, 'Position',[0.04 0 0.81 0.05]);
                
            end
            
            behaviour = ones(nf, 1);
            
            if isnan(frame) || frame <= 0 || frame > nf
                frame = 1;
            end
            set(handles.frame, 'Value', frame);
            
            if stacktucam
                rightdisplacementx = originalsizex / 2;
                rightdisplacementy = 0;
                set(handles.alignmentx, 'String', num2str(rightdisplacementx));
                set(handles.alignmenty, 'String', num2str(rightdisplacementy));
            end
            
            setrightdisplacementx(hobj,eventdata);
            setrightdisplacementy(hobj,eventdata);
            updatesubchannelsizes;
            
            numberofregions = zeros(nf,1);
            
            excludedarea = false(subchannelsizey, subchannelsizex);

            set(handles.filepreviewpanel,'Visible','off');
            set(handles.previewpanel,'Visible','on');
            if nf > 1
                set(handles.frame,'Visible','on','Enable','on','Min',1,'Max',nf, 'SliderStep',[1/(nf-1) 10/(nf-1)]); %Sliderstep is set to 10 frames per click
                set(handles.minusfifty, 'Visible', 'on', 'Enable', 'on');
                set(handles.plusfifty, 'Visible', 'on', 'Enable', 'on');
            else
                set(handles.frame,'Visible','off','Enable','off','Min',1,'Max',2, 'SliderStep',[1 1]); %Fallback in case of having only 1 frame
                set(handles.minusfifty, 'Visible', 'off', 'Enable', 'off');
                set(handles.plusfifty, 'Visible', 'off', 'Enable', 'off');
            end
            set(handles.showneurons,'Value',0);
            set(handles.img,'Visible','on');
            file = newfile;
            
            canbrowsemovie = true;
            canshowneurons = false;
            cansetchannel = false;
            cansetalignment = true;
            candetect = false;
            canselectregion = false;
            canadjustregion = false;
            canadjustmeasurement = false;
            cancalculate = false;
            cansetfile = false;
            canplot = false;
            canmanipulate = false;
                        
            % Update values
            setradius(hobj,eventdata);
            setcorrectionsearchradius(hobj,eventdata);
            setalignmentsearchradius(hobj, eventdata);
            setminimalneuronsize(hobj,eventdata);
            
            set(handles.load, 'String', 'Unload movie', 'Enable', 'on');
            
            %Enable further controls if alignment values are carried over from another analysis
            updateifalignmentset(hobj, eventdata);
            
            %Finally, show frame
            dontupdateframe = false;
            showframe(hobj,eventdata);
        else % if it's an unload command
%            set(handles.alignmentdisplay, 'String', 'Alignment vector = 0;0');
%            set(handles.alignmentdisplay, 'String', '0;0');
%            set(handles.alignmentx, 'String', '0');
%            set(handles.alignmenty, 'String', '0');
%            set(handles.croplmiddle, 'String', num2str(leftwidth));
%            set(handles.croprmiddle, 'String', num2str(rightdisplacementx+unusablerightx));

            set([controlzstack controlz], 'Visible', 'off');

            cansetfile = true;
            cansetalignment = false;
            cancrop = false;
            candetect = false;
            canselectregion = false;
            canadjustregion = false;
            canadjustmeasurement = false;
            cancalculate = false;
            canplot = false;
            canmanipulate = false;
            cansetchannel = false;
            stackcache = 0;
            
            bfreader = [];
            
            speedreadable = false;
            
            set(handles.img, 'Visible', 'off');
            set(handles.fimg, 'Visible', 'on');

            selectfile(hobj, eventdata);
            set(handles.load, 'String', 'Load movie');
        end
        
        dontupdatevisibility = false;
        updatevisibility;
    end

    function readspeed (hobj, eventdata) %#ok<INUSD>
                
        disableeverythingtemp;
        
        set(handles.readspeed, 'String', 'Reading speed...', 'Enable', 'off');
        
        drawnow;
        
        successfullyread = false;
            
        %if we haven't found stage position tags in the tiff file,
        %we may still read stage position from a terminal output textfile
        try
            onestagemorestacks = false; %whether we have a single stage position textfile covering multiple stack files (in which case we'll need to figure out which part of the textfile corresponds to this stack)
            positionfile = [];
            dots = strfind(newfile, '.');
            %first, try looking for same filename, except with a txt extension
            matchingwouldbe = newfile;
            matchingwouldbe = [matchingwouldbe(1:dots(end)) 'txt']; %must take care because the file extension may be shorter or longer than the 3 characters we're changing it to
            if exist(fullfile(currentpath, matchingwouldbe), 'file') == 2
                positionfile = fopen(fullfile(currentpath, matchingwouldbe), 'r');
            else
                %if the previous file wasn't found, and the last character of the filename before the extension is a number, try ignoring that number in the textfile name
                currentstacknumber = str2double(newfile(dots(end)-1))+1; %currentstacknumber will be used later when figuring out what overall frame the first frame of the current movie is
                if ~isnan(currentstacknumber)
                    matchingwouldbe = [newfile(1:dots(end)-2) '.txt'];
                    if exist(fullfile(currentpath, matchingwouldbe), 'file') == 2
                        positionfile = fopen(fullfile(currentpath, matchingwouldbe), 'r');
                    end
                    onestagemorestacks = true;
                end
            end

            if ~isempty(positionfile)
                fprintf('Found stage position textfile %s . Attempting to read it...\n', matchingwouldbe);
                stagepositionstring = [];
                currentline = NaN;
                i = 0;
                while ~(~ischar(currentline) && currentline == -1) %Until we hit EOF (where fgets returns -1)
                    currentline = fgets(positionfile);
                    if any((currentline >= '0' & currentline <= '9') | currentline == '-' | currentline == ',') %iff there is any numerical-ish character, we store the line
                        i = i+1;
                        stagepositionstring{i} = currentline; %#ok<AGROW>
                    end
                end
                framex = [];
                framey = [];
                for i=1:numel(stagepositionstring)
                    commas = strfind(stagepositionstring{i}, ',');
                    framex(i) = str2double(stagepositionstring{i}(1:commas(1)-1));
                    framey(i) = str2double(stagepositionstring{i}(commas(1)+1:commas(2)-1));
                end
                fclose(positionfile);
                fprintf('Stage position string read successfully. Attempting to interpret it...\n');

                if onestagemorestacks %now we need to figure out how many frames there are in all of the stacks combined
                    overallnfs = zeros(1, 10);
                    behaviours = [];
                    for i=1:10
                        matchingwouldbe = [newfile(1:dots(end)-2) num2str(i-1) '-analysisdata.mat'];
                        if exist(matchingwouldbe, 'file') == 2
                            loadednow = load(matchingwouldbe, 'behaviour');
                            if size(loadednow.behaviour, 1) > size(loadednow.behaviour, 2)
                                loadednow.behaviour = loadednow.behaviour';
                            end
                            behaviours = [behaviours loadednow.behaviour]; %#ok<AGROW>
                            overallnfs(i) = numel(loadednow.behaviour);
                        else
                            break;
                        end
                    end
                else %only a single stack
                    overallnfs = nf;
                    behaviours = behaviour;
                end

                if behaviours(1) ~= CONST_BEHAVIOUR_BADFRAME
                    startstackframe = NaN;
                else
                    startstackframe = find(behaviours ~= CONST_BEHAVIOUR_BADFRAME, 1, 'first');
                end
                if behaviours(end) ~= CONST_BEHAVIOUR_BADFRAME
                    endstackframe = NaN;
                else
                    endstackframe = find(behaviours ~= CONST_BEHAVIOUR_BADFRAME, 1, 'last');
                end

                speeds = [NaN hypot(diff(framex), diff(framey))];
                accelerations = [NaN diff(speeds)];

                if speeds(2) ~= 0 %using index 2 because index 1 is always set to NaN (because there is no previous frame to calculate displacement from)
                    startstageframe = NaN;
                else
                    startstageframe = find(abs(accelerations)>0, 1, 'first');
                end
                if speeds(end) ~= 0
                    endstageframe = NaN;
                else
                    endstageframe = find(abs(accelerations)>0, 1, 'last');
                end

                if isempty(startstackframe) || isnan(startstackframe)
                    warningmessage = ['Warning: unable to determine when the valid interval (where both stage position and imaging data are available) begins.' ...
                        'The first several frames at the very beginning of the recording (of the first movie, if this is a multi-file imaging stack) should be set to "bad frame"s up until the frame where you see the stage first begin moving.' ...
                        'You may proceed by assuming that the stage began moving in the first frame of the stack, but for accuracy it is recommended that you cancel now and try again after setting it up properly.'];
                    if strcmp(questdlg(warningmessage,'Unable to determine valid interval','Proceed with assumptions','Cancel and set it up properly','Cancel and set it up properly'),'Cancel and set it up properly')
                        frametime = NaN;
                        framex = NaN;
                        framey = NaN;
                        set(handles.readspeed, 'String', 'Read speed', 'Enable', 'on');
                        updatevisibility;
                        return;
                    else
                        startstackframe = 1;
                    end
                end
                if isempty(endstackframe) || isnan(endstackframe)
                    warningmessage = ['Warning: unable to determine when the valid interval (where both stage position and imaging data are available) ends.' ...
                        'The last several frames at the very end of the recording (of the last movie, if this is a multi-file imaging stack) should be set to "bad frame"s after the frame where you see the stage finally ending its last move.' ...
                        'You may proceed by assuming that the stage stopped moving in the last frame of the stack, but for accuracy it is recommended that you cancel now and try again after setting it up properly.'];
                    if strcmp(questdlg(warningmessage,'Unable to determine valid interval','Proceed with assumptions','Cancel and set it up properly','Cancel and set it up properly'),'Cancel and set it up properly')
                        frametime = NaN;
                        framex = NaN;
                        framey = NaN;
                        set(handles.readspeed, 'String', 'Read speed', 'Enable', 'on');
                        updatevisibility;
                        return;
                    else
                        endstackframe = sum(overallnfs);
                    end
                end
                if isempty(startstageframe) || isnan(startstageframe)
                    warningmessage = ['Warning: unable to determine when the valid interval (where both stage position and imaging data are available) begins.' ...
                        'The stage is supposed to be stationary when position logging begins so that its first movement could be used as a landmark for time-synchronisation.' ...
                        'You may proceed by assuming that the stage started moving exactly when position logging began, but this will probably lead to inaccuracy.'];
                    if strcmp(questdlg(warningmessage,'Unable to determine valid interval','Proceed with assumptions','Cancel','Cancel'),'Cancel')
                        frametime = NaN;
                        framex = NaN;
                        framey = NaN;
                        set(handles.readspeed, 'String', 'Read speed', 'Enable', 'on');
                        updatevisibility;
                        return;
                    else
                        startstageframe = 1;
                    end
                end
                if isempty(endstageframe) || isnan(endstageframe)
                    warningmessage = ['Warning: unable to determine when the valid interval (where both stage position and imaging data are available) ends.' ...
                        'The stage is supposed to be stationary when position logging ends so that its last movement could be used as a landmark for time-synchronisation.' ...
                        'You may proceed by assuming that the stage finished moving exactly when position logging stopped, but this will probably lead to inaccuracy.'];
                    if strcmp(questdlg(warningmessage,'Unable to determine valid interval','Proceed with assumptions','Cancel','Cancel'),'Cancel')
                        frametime = NaN;
                        framex = NaN;
                        framey = NaN;
                        set(handles.readspeed, 'String', 'Read speed', 'Enable', 'on');
                        updatevisibility;
                        return;
                    else
                        endstageframe = 1;
                    end
                end

                behavioursplusminus = ceil((max(behaviours)-min(behaviours))/10);
                accelerationsplusminus = ceil((max(accelerations)-min(accelerations))/10);

                if behavioursplusminus == 0
                    behavioursplusminus = 0.5;
                end
                if accelerationsplusminus == 0
                    accelerationsplusminus = 0.5;
                end

                synchfigure = figure;
                subplot(2, 1, 1);
                plot(behaviours);
                title('On-camera behaviour', 'FontSize', 14);
                xlabel('Frame', 'FontSize', 12);
                ylabel('Behaviour', 'FontSize', 12);
                hold on;
                line([startstackframe startstackframe], [min(behaviours)-behavioursplusminus max(behaviours)+behavioursplusminus], 'color', 'r');
                line([endstackframe endstackframe], [min(behaviours)-behavioursplusminus max(behaviours)+behavioursplusminus], 'color', 'r');
                subplot(2, 1, 2);
                plot(accelerations);
                title('Stage acceleration', 'FontSize', 14);
                xlabel('Stage-timepoint', 'FontSize', 12);
                ylabel('Acceleration', 'FontSize', 12);
                hold on;
                line([startstageframe startstageframe], [min(accelerations)-accelerationsplusminus max(accelerations)+accelerationsplusminus], 'color', 'r');
                line([endstageframe endstageframe], [min(accelerations)-accelerationsplusminus max(accelerations)+accelerationsplusminus], 'color', 'r');

                if strcmp(questdlg(sprintf('The red lines represent the start- and endpoints of the valid interval. There are %d valid stage position datapoints corresponding to %d valid frames (%.2f stage position datapoints per frame). Does it make sense, or do you notice anything wrong?', endstageframe-startstageframe, endstackframe-startstackframe, (endstageframe-startstageframe)/(endstackframe-startstackframe)),'Synchronisation confirmation check','It makes sense, proceed','It looks wrong, cancel','It makes sense, proceed'),'It makes sense, proceed')
                    delete(synchfigure);

                    resampledpoints = linspace(startstageframe,endstageframe,endstackframe-startstackframe+1);

                    resampledframex = interp1(1:numel(framex), framex, resampledpoints);
                    resampledframey = interp1(1:numel(framey), framey, resampledpoints);

                    if onestagemorestacks
                        framesbeforethisstack = sum(overallnfs(1:currentstacknumber-1));
                        if framesbeforethisstack > 0
                            validframesbeforethisstack = framesbeforethisstack - startstageframe + 1;
                        else
                            validframesbeforethisstack = framesbeforethisstack;
                        end
                    else
                        framesbeforethisstack = 0;
                        validframesbeforethisstack = 0;
                    end

                    validframesinthisstackfrom = 1;
                    validframesinthisstackuntil = nf;
                    if ~onestagemorestacks || currentstacknumber == 1 %first stack
                        validframesinthisstackfrom = startstackframe;
                        invalidstartingframesinthisstack = startstackframe-1;
                    else
                        invalidstartingframesinthisstack = 0;
                    end
                    if ~onestagemorestacks || currentstacknumber == 10 || overallnfs(currentstacknumber+1) == 0 %last stack
                        validframesinthisstackuntil = endstackframe-framesbeforethisstack;
                        invalidendingframesinthisstack = sum(overallnfs)-endstackframe;
                    else
                        invalidendingframesinthisstack = 0;
                    end
                    validframesinthisstack = validframesinthisstackuntil-validframesinthisstackfrom+1;

                    framex = [NaN(1, invalidstartingframesinthisstack) resampledframex(validframesbeforethisstack+1:validframesbeforethisstack+validframesinthisstack) NaN(1, invalidendingframesinthisstack)];
                    framey = [NaN(1, invalidstartingframesinthisstack) resampledframey(validframesbeforethisstack+1:validframesbeforethisstack+validframesinthisstack) NaN(1, invalidendingframesinthisstack)];

                    %Asking for user confirmation of the frame rate
                    userduration = 60; %default answer
                    enteringfirst = true;
                    frameduration = NaN;
                    while enteringfirst || isnan(frameduration)
                        enteringfirst = false;
                        if isnan(userduration)
                            userdurationstring = '';
                        else
                            userdurationstring = num2str(userduration);
                        end
                        userduration = inputdlg('Time between successive frames in the stack (in ms):', 'Enter time interval', 1, {userdurationstring}, 'on');
                        userduration = str2double(userduration);
                        if isempty(userduration) %the user clicked cancel
                            framex = NaN;
                            framey = NaN;
                            frametime = NaN;
                            set(handles.readspeed, 'String', 'Read speed', 'Enable', 'on');
                            updatevisibility;
                            return;
                        elseif userduration > 0
                            frameduration = userduration;
                        end
                    end

                    frametime = 0:frameduration:(nf-1)*frameduration;

                    fprintf('Stage position read and interpreted successfully.\n');

                    successfullyread = true;

                else
                    frametime = NaN;
                    framex = NaN;
                    framey = NaN;
                end

            end
        catch, err = lasterror; %#ok<CTCH,LERR>
            fprintf('%s\n', err.message);
            frametime = NaN;
            framex = NaN;
            framey = NaN;
        end
            
        
        if ~successfullyread
            if strcmp(questdlg('Could not find stage position data. Assume static stage?','No stage position data','Assume static stage','Cancel','Assume static stage'),'Assume static stage')
                %asking the user about the frame rate
                userduration = 100; %default answer
                enteringfirst = true;
                frameduration = NaN;
                while enteringfirst || isnan(frameduration)
                    enteringfirst = false;
                    if isnan(userduration)
                        userdurationstring = '';
                    else
                        userdurationstring = num2str(userduration);
                    end
                    userduration = inputdlg('Time between successive frames in the stack (in ms):', 'Enter time interval', 1, {userdurationstring}, 'on');
                    userduration = str2double(userduration);
                    if isempty(userduration) %the user clicked cancel
                        framex = NaN;
                        framey = NaN;
                        frametime = NaN;
                        set(handles.readspeed, 'String', 'Read speed', 'Enable', 'on');
                        updatevisibility;
                        return;
                    elseif userduration > 0
                        frameduration = userduration;
                    end
                end
                questdlg('Now click on two points the distance between which is known in order to determine the scaling factor','Determining the scale','Ok','Ok');
                %asking the user about the scaling
                scalingcrosshairradius = round(min([subchannelsizex, subchannelsizey])/30);
                [x(1), y(1), clicktype] = zinput('crosshair', 'radius', scalingcrosshairradius, 'colour', 'b');
                if ~strcmpi(clicktype, 'normal')
                    framex = NaN;
                    framey = NaN;
                    frametime = NaN;
                    updatevisibility;
                    return;
                end
                line([x(1)-scalingcrosshairradius x(1)+scalingcrosshairradius], [y(1) y(1)], 'color', 'b');
                line([x(1) x(1)], [y(1)-scalingcrosshairradius y(1)+scalingcrosshairradius], 'color', 'b');
                [x(2), y(2), clicktype] = zinput('crosshair', 'radius', scalingcrosshairradius, 'colour', 'r');
                if ~strcmpi(clicktype, 'normal')
                    framex = NaN;
                    framey = NaN;
                    frametime = NaN;
                    updatevisibility;
                    return;
                end
                line([x(2)-scalingcrosshairradius x(2)+scalingcrosshairradius], [y(2) y(2)], 'color', 'r');
                line([x(2) x(2)], [y(2)-scalingcrosshairradius y(2)+scalingcrosshairradius], 'color', 'r');
                pixeldistance = hypot(x(2)-x(1), y(2)-y(1));
                micrometers = inputdlg(sprintf('Distance in pixels: %f .\nEnter the actual distance in micrometers to determine the scaling factor:', pixeldistance));
                if ~isempty(micrometers) %if the user did not cancel
                    micrometers = str2double(char(micrometers));
                    framex = micrometers/pixeldistance;
                    framey = micrometers/pixeldistance;
                    frametime = (0:nf-1)*frameduration;
                    questdlg('Framerate and scaling factor set up successfully.','Speed parameters set up','Ok','Ok');
                end
                wherecrosshairs = findobj(handles.img, 'type', 'line');
                delete(wherecrosshairs);
            end
        end
        
        set(handles.readspeed, 'String', 'Read speed', 'Enable', 'on');
        
        updatevisibility;
        
    end

    function setalignment(hobj, eventdata)
        
        if stacktucam
            questdlg('The alignment between the two stacks in a dualmovie is assumed to be perfect (for now). Some kind of alignment-correction will probably be implemented later.', 'Alignment', 'OK', 'OK');
            return;
        end
        
        clearallregions;
        
        set(handles.regionnamedisplay,'String',selectedname);
        set(handles.regionnametext,'String','Region name (0)');
        set(handles.adjustleft,'String','Left (0;0)');
        set(handles.adjustright,'String','Right (0;0)');
        set(handles.leftradiusdisplay,'String', num2str(selectedradiusy));
        set(handles.rightradiusdisplay,'String', num2str(selectedradiusc));

        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue ~= 1)
            set(handles.channel, 'Value', 1);
            needsrefresh = true;
        end
        showframe(hobj, eventdata); %Always refresh now because regions may have been cleared
        
        %{
        set(handles.channel, 'Enable', 'off');
        set(controlbrowsemovie, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        set(controlselectregion, 'Enable', 'off');
        set(controlcalculate, 'Enable', 'off');
        %}
        
        disableeverythingtemp;
        
        if stacktucam
            alignmentimage = [readframe(frame, 1) readframe(frame, 2)];
        else
            alignmentimage = readframe(frame);
        end
        
        [x(1), y(1)] = zinput('square', 'Radius', alignmentsearchradius, 'Colour', 'r');
        [x(2), y(2)] = zinput('square', 'Radius', alignmentsearchradius, 'Colour', 'r');
        [x, ix] = sort(x);
        y = y(ix);

        % Peak correction
        % Defining limits that are not out-of-bounds
        leftpeaksearchminx = max(floor(x(1))-alignmentsearchradius, 1);
        leftpeaksearchminy = max(floor(y(1))-alignmentsearchradius, 1);
        leftpeaksearchmaxx = min(floor(x(2))-alignmentsearchradius, ceil(x(1))+alignmentsearchradius);
        leftpeaksearchmaxy = min(originalsizey, ceil(y(1))+alignmentsearchradius);
        % looks for left peak locally
        [leftpeak, leftpeaky] = max(alignmentimage(leftpeaksearchminy:leftpeaksearchmaxy,leftpeaksearchminx:leftpeaksearchmaxx));
        [labspeak, leftpeakx] = max(leftpeak); % max works on vectors so have to do it like this
        leftpeaky = leftpeaky(leftpeakx); % was a vector before, now a scalar
        leftpeakx = leftpeakx + leftpeaksearchminx - 1;
        leftpeaky = leftpeaky + leftpeaksearchminy - 1;

        % Defining limits that are not out-of-bounds
        rightpeaksearchminx = max(floor(x(2))-alignmentsearchradius, ceil(x(1))+alignmentsearchradius);
        rightpeaksearchminy = max(floor(y(2))-alignmentsearchradius, 1);
        rightpeaksearchmaxx = min(originalsizex, ceil(x(2))+alignmentsearchradius);
        rightpeaksearchmaxy = min(originalsizey, ceil(y(2))+alignmentsearchradius);
        % looks for right peak locally
        [rightpeak, rightpeaky] = max(alignmentimage(rightpeaksearchminy:rightpeaksearchmaxy,rightpeaksearchminx:rightpeaksearchmaxx));
        [rabspeak, rightpeakx] = max(rightpeak); % max works on vectors so have to do it like this
        rightpeaky = rightpeaky(rightpeakx); % was a vector before, now a scalar
        rightpeakx = rightpeakx + rightpeaksearchminx - 1;
        rightpeaky = rightpeaky + rightpeaksearchminy - 1;

        rightdisplacementx = round(rightpeakx) - round(leftpeakx)+1;
        rightdisplacementy = round(rightpeaky) - round(leftpeaky)+1;

        set(handles.alignmentx, 'String', num2str(rightdisplacementx));
        set(handles.alignmenty, 'String', num2str(rightdisplacementy));

        crosssize = 10;
        hold on;
        plot([rightpeakx-crosssize rightpeakx+crosssize], [rightpeaky rightpeaky], '-r', 'LineWidth', 1, 'MarkerSize', 1);
        plot([rightpeakx rightpeakx], [rightpeaky-crosssize rightpeaky+crosssize], '-r', 'LineWidth', 1, 'MarkerSize', 1);
        plot([leftpeakx-crosssize leftpeakx+crosssize], [leftpeaky leftpeaky], '-r', 'LineWidth', 1, 'MarkerSize', 1);
        plot([leftpeakx leftpeakx], [leftpeaky-crosssize leftpeaky+crosssize], '-r', 'LineWidth', 1, 'MarkerSize', 1);
        hold off;
        
        questdlg('Alignment set up', 'Alignment visualisation', 'OK', 'OK');
        
        updateifalignmentset(hobj, eventdata);
        updatevisibility;
        
        if (needsrefresh)
            set(handles.channel, 'Value', previouschannelvalue);
        end
        showframe(hobj, eventdata);
        colormap(jet);

    end

    function setrightdisplacementx(hobj, eventdata)
        
        set(handles.regionnamedisplay,'String',selectedname);
        set(handles.regionnametext,'String','Region name (0)');
        set(handles.adjustleft,'String','Left (0;0)');
        set(handles.adjustright,'String','Right (0;0)');
        set(handles.leftradiusdisplay,'String', num2str(selectedradiusy));
        set(handles.rightradiusdisplay,'String', num2str(selectedradiusc));
        
        temprightdisplacementx = round(str2double(get(handles.alignmentx, 'String')));
        if isnan(temprightdisplacementx)
            temprightdisplacementx = round(originalsizex/2)+1; %good initial guess. The +1 is because it tells the x-coordinate of the first pixel that's used in the right channel, so the pixel at round(originalsizex/2) would typically still belong to the left channel
        end
		temprightdisplacementx = bound(temprightdisplacementx, 2, originalsizex);
        rightdisplacementx = temprightdisplacementx;
        set(handles.alignmentx, 'String', num2str(rightdisplacementx));
        
        updateifalignmentset(hobj, eventdata);
    end

    function setrightdisplacementy(hobj, eventdata)
        
        set(handles.regionnamedisplay,'String',selectedname);
        set(handles.regionnametext,'String','Region name (0)');
        set(handles.adjustleft,'String','Left (0;0)');
        set(handles.adjustright,'String','Right (0;0)');
        set(handles.leftradiusdisplay,'String', num2str(selectedradiusy));
        set(handles.rightradiusdisplay,'String', num2str(selectedradiusc));
        
        temprightdisplacementy = round(str2double(get(handles.alignmenty, 'String')));
        if isnan(temprightdisplacementy)
            temprightdisplacementy = 0; %good initial guess
        end
		temprightdisplacementy = bound(temprightdisplacementy, -originalsizey, originalsizey);
        rightdisplacementy = temprightdisplacementy;
        set(handles.alignmenty, 'String', num2str(rightdisplacementy));
        
        updateifalignmentset(hobj, eventdata)
    end

    function updateifalignmentset(hobj, eventdata)
        if (~isnan(rightdisplacementx) && ~isnan(rightdisplacementy))
            previouslydontupdateframe = dontupdateframe; %storing dontupdateframe state prior to entering this function
            dontupdateframe = true; %setting the crop updates the frame automatically. We will update at the end so no need to do it several times
            if (isnan(leftwidth) || leftwidth == 0) && (isnan(unusablerightx) || unusablerightx == 0)
                %Starting guesses for channel division
                leftwidth = rightdisplacementx-1;
                unusablerightx = 0;
                set(handles.croplmiddle, 'String', num2str(leftwidth));
                set(handles.croprmiddle, 'String', num2str(rightdisplacementx+unusablerightx));
            end
            
            %check and potentially update middle cropping based on the
            %potentially new subchannel size due to the new alignment
            %dontupdateframe = true;
            setcroplmiddle(hobj, eventdata);
            setcroprmiddle(hobj, eventdata);
            %also check and potentially update crop settings because the
            %new alignment can potentially result in a subchannel size of
            %less than zero if high crop settings are left over from the
            %pervious alignment
            setcroptop(hobj, eventdata);
            setcropbottom(hobj, eventdata);
            setcropleft(hobj, eventdata);
            setcropright(hobj, eventdata);
            %dontupdateframe = false;

            cancrop = true;

            updatevisibility;
            setpixelnumber(hobj, eventdata);
            setpercentile(hobj, eventdata);
            dontupdateframe = previouslydontupdateframe; %we return dontupdateframe state to its previous value
            showframe
        end
    end

    function setcropall (hobj, eventdata)
        %clearallregions;
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue == 1 || previouschannelvalue == 8)
            set(handles.channel, 'Value', 2);
            needsrefresh = true;
        end
        cropleft = 0;
        set(handles.cropleft, 'String', num2str(cropleft));
        cropright = 0;
        set(handles.cropright, 'String', num2str(cropright));
        croptop = 0;
        set(handles.croptop, 'String', num2str(croptop));
        cropbottom = 0;
        set(handles.cropbottom, 'String', num2str(cropbottom));
        updatesubchannelsizes;
        showframe(hobj, eventdata);
        
        %{
        set(handles.channel, 'Enable', 'off');
        set(controlbrowsemovie, 'Enable', 'off');
        set(controlcrop, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        %}
        disableeverythingtemp;
        
        x = NaN(4,1);
        y = NaN(4,1);
        for i=1:4
            [x(i), y(i)] = zinput('axes', 'Colour', 'r');
        end
        [x, ix] = sort(x); %#ok<NASGU>
        [y, iy] = sort(y); %#ok<NASGU>
        x = round(x);
        y = round(y);
        if (x(2) >= 1 && x(2) < subchannelsizex)
            cropleft = x(2)-1;
            set(handles.cropleft, 'String', num2str(cropleft));
        else
            fprintf('Warning: left crop value is outside of image size bounds; keeping previous value.\n');
        end
        %if the corners were specified in two subimages at the same time, overlay the ones from the two channels
        if ((get(handles.channel, 'Value') == 2 || get(handles.channel, 'Value') == 3) && x(3) > subchannelsizex)
            x(3) = x(3) - subchannelsizex;
            x(4) = x(4) - subchannelsizex;
        end
        if (x(3) > 1 && x(3) <= subchannelsizex);
            cropright = subchannelsizex - x(3);
            set(handles.cropright, 'String', num2str(cropright));
        else
            fprintf('Warning: right crop value is outside of image size bounds; keeping previous value.\n');
        end
        if (y(2) > 1 && y(2) <= subchannelsizey)
            croptop = y(2) - 1;
            set(handles.croptop, 'String', num2str(croptop));
        else
            fprintf('Warning: bottom crop value is outside of image size bounds; keeping previous value.\n');
        end
        if (y(3) >= 1 && y(3) < subchannelsizey)
            cropbottom = subchannelsizey - y(3);
            set(handles.cropbottom, 'String', num2str(cropbottom));
        else
            fprintf('Warning: top crop value is outside of image size bounds; keeping previous value.\n');
        end
        dontupdateframe = true;
        setcroptop;
        setcropbottom;
        setcropleft;
        setcropright;
        dontupdateframe = false;
%        updatesubchannelsizes;
        if (needsrefresh)
            set(handles.channel, 'Value', previouschannelvalue);
        end
        showframe(hobj, eventdata);
        updatevisibility;
    end

    function setcropmiddle (hobj, eventdata)
        
        %clearallregions;
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue ~= 1)
            set(handles.channel, 'Value', 1);
            needsrefresh = true;
            showframe(hobj, eventdata);
        end
        %{
        set(handles.channel, 'Enable', 'off');
        set(controlbrowsemovie, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        %}
        disableeverythingtemp;
        
        [x(1), y(1)] = zinput('vertical', 'Colour', 'r');
        [x(2), y(2)] = zinput('vertical', 'Colour', 'r'); %#ok<NASGU>
        [x, ix] = sort(x); %#ok<NASGU>
        x = round(x);
        if (x(1) >= 1 && x(1) <= originalsizex && x(2) >= 1 && x(2) <= originalsizex )
            leftwidth = x(1);
            unusablerightx = max(x(2) - rightdisplacementx,0);
            set(handles.croplmiddle, 'String', num2str(leftwidth));
            set(handles.croprmiddle, 'String', num2str(rightdisplacementx+unusablerightx));
            dontupdateframe = true;
            setcroplmiddle; %Making sure that the new crop values are sensible, i.e. that they don't produce subchannel sizes below 1. They come together after they've been set so that there's no clash with e.g. trying to set lmiddlecrop higher than rmiddlecrop (before rmiddlecrop is updated). This also updates subchannel sizes
            setcroprmiddle;
            dontupdateframe = false;
        else
            fprintf('Warning: crop values are outside of image size bounds; keeping previous values.\n');
        end
        if (needsrefresh)
            set(handles.channel, 'Value', previouschannelvalue);
        end
        showframe(hobj, eventdata);
        updatevisibility;
    end

    function setfilter (hobj, eventdata) %#ok<INUSD>
        filterstring = get(handles.filter, 'String');
        
        %The string format we expect is '[X Y], S' (without the quotation marks),
        %where X and Y stand for the size of the filter (natural numbers), and S stands for
        %its sigma value (nonnegative rational number)
        %If 0 is passed as the string, use of filters is disabled
        
        if str2double(filterstring) == 0 %then we're not going to use filters at all
            gaussianx = 0;
            gaussiany = 0;
            gaussians = 0;
        elseif str2double(filterstring) > 0 %If the argument is a single value, we approximate the size of the matrix based on the sigma-value
            gaussians = str2double(filterstring);
            gaussianx = ceil(6*gaussians); %the contribution of pixels farther than 3sigma away are effectively zero, so using a filter-size of at least 6sigma*6 gives a good enough approximation
            if mod(gaussianx,2) == 0 %ensuring that the size of the filter matrix is odd so that it has a centre point
                gaussianx = gaussianx + 1;
            end
            gaussiany = gaussianx;
        else
            i=0;
            firstfrom = NaN; %X-size of the filter
            firstto = NaN;
            secondfrom = NaN; %Y-size of the filter
            secondto = NaN;
            thirdfrom = NaN; %Sigma-value of the filter
            thirdto = NaN;
            while i<numel(filterstring)
                i=i+1;
                if isnan(firstfrom) && filterstring(i) == '['
                    while i<numel(filterstring)
                        i=i+1;
                        if ~isnan(str2double(filterstring(i))) %if it's a number
                            firstfrom = i;
                            break;
                        end
                    end
                    if isnan(firstfrom) %haven't found a number for the first value; exit parent loop and complain
                        break;
                    end
                    while i<numel(filterstring)
                        i=i+1;
                        if isnan(str2double(filterstring(i))) && filterstring(i) ~= '.' %if it's not a number, the
                            firstto = i-1;
                            break;
                        end
                    end
                end
                if ~isnan(firstfrom) && isnan(secondfrom) && (filterstring(i) == ' ' || filterstring(i) == ',' || filterstring(i) == ';')
                    while i<numel(filterstring)
                        i=i+1;
                        if ~isnan(str2double(filterstring(i))) %if it's a number
                            secondfrom = i;
                            break;
                        end
                    end
                    if isnan(secondfrom) %haven't found a number for the first value; exit parent loop and complain
                        break;
                    end
                    while i<numel(filterstring)
                        i=i+1;
                        if isnan(str2double(filterstring(i))) && filterstring(i) ~= '.' %if it's not a number, the
                            secondto = i-1;
                            break;
                        end
                    end
                end
                if ~isnan(firstfrom) && ~isnan(secondfrom) && isnan(thirdfrom) && filterstring(i) == ']'
                    while i<numel(filterstring)
                        i=i+1;
                        if ~isnan(str2double(filterstring(i))) %if it's a number
                            thirdfrom = i;
                            break;
                        end
                    end
                    while i<numel(filterstring)
                        i=i+1;
                        if isnan(str2double(filterstring(i))) && filterstring(i) ~= '.' %if it's not a number, the
                            thirdto = i-1;
                            break;
                        end
                    end
                    if i == numel(filterstring) %If we reached the end of the string, we must make a decision about the end of the third number
                        if ~isnan(str2double(filterstring(i))) %if it's a number
                            thirdto = i;
                        else
                            thirdto = i-1;
                        end
                    end
                    break;
                end
            end

            newfilterok = false;
            if (firstfrom <= firstto) && (firstto < secondfrom) && (secondfrom <= secondto) && (secondto < thirdfrom) && (thirdfrom <= thirdto) %Number positions in the string make sense
                firstnumber = round(str2double(filterstring(firstfrom:firstto))); %X-size of the filter
                secondnumber = round(str2double(filterstring(secondfrom:secondto))); %Y-size of the filter
                thirdnumber = str2double(filterstring(thirdfrom:thirdto)); %Sigma-value of the filter
                if ~isnan(firstnumber) && ~isnan(secondnumber) && ~isnan(thirdnumber) && firstnumber > 0 && secondnumber > 0 && thirdnumber > 0
                    gaussianx = firstnumber;
                    gaussiany = secondnumber;
                    gaussians = thirdnumber;
                    newfilterok = true;
                end
            end
            if ~newfilterok
                fprintf('Warning: unable to interpret the newly specified filter. Continuing to use previous filter instead. The expected filter format is ''[X Y], S'' (without the quotation marks), where X and Y stand for the size of the filter (natural numbers), and S stands for its sigma value (nonnegative rational number). The use of filters can be disabled by setting the value to a single 0.\n');
            end
        end
        
        if gaussianx == 0
            gaussianfilter = NaN; %so that if somehow gaussianfilter would be used even though it shouldn't, we will see the error
            set(handles.filter, 'String', num2str(0));
        else
            gaussianfilter = fspecial('gaussian',[gaussianx,gaussiany],gaussians);
            set(handles.filter, 'String', ['[' num2str(gaussianx) ' ' num2str(gaussiany) '], ' num2str(gaussians)]);
%            fprintf('%d-%d\n%d-%d\n%d-%d\n', firstfrom, firstto, secondfrom, secondto, thirdfrom, thirdto);
        end
        showframe;

    end

    function setpixelthreshold(hobj, eventdata)
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue ~= 4)
            set(handles.channel, 'Value', 4);
            needsrefresh = true;
        end
        set(controlselectregion, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        set(handles.channel, 'Enable', 'off');
        set(handles.frame, 'Enable', 'off');
        set(handles.setframe, 'Enable', 'off');
        set(handles.makefigure, 'Enable', 'off');
        set(handles.plusfifty, 'Enable', 'off');
        set(handles.minusfifty, 'Enable', 'off');
        if needsrefresh
            showframe(hobj, eventdata);
        end
        thresholdknown = false;
        while (thresholdknown == false)
            [x, y] = zinput('crosshair', 'Colour', 'r');
            x = round(x);
            y = round(y);
            if x >= 1 && x <= subchannelsizex && y >= 1 && y <= subchannelsizey
                thresholdknown = true;
            end
        end
        L = LEFT(frame);
        leftthreshold = L(y,x);
        if isnan(leftthreshold) || leftthreshold < 0
            leftthreshold = 0;
        end
        set(handles.leftthresholdbox, 'String', num2str(leftthreshold));
        
        set(handles.channel, 'Value', 5);
        showframe(hobj, eventdata);
        thresholdknown = false;
        while (thresholdknown == false)
            [x, y] = zinput('crosshair', 'Colour', 'r');
            x = round(x);
            y = round(y);
            if x >= 1 && x <= subchannelsizex && y >= 1 && y <= subchannelsizey
                thresholdknown = true;
            end
        end
        R = RIGHT(frame);
        rightthreshold = R(y,x);
        if isnan(rightthreshold) || rightthreshold < 0
            rightthreshold = 0;
        end
        set(handles.rightthresholdbox, 'String', num2str(rightthreshold));
        
        set(controlselectregion, 'Enable', 'on');
        set(controladjustregion, 'Enable', 'on')
        set(handles.channel, 'Enable', 'on');
        set(handles.frame, 'Enable', 'on');
        set(handles.setframe, 'Enable', 'on');
        set(handles.makefigure, 'Enable', 'on');
        set(handles.plusfifty, 'Enable', 'on');
        set(handles.minusfifty, 'Enable', 'on');
        
        set(handles.channel, 'Value', previouschannelvalue);
        if (previouschannelvalue ~= 5) %we're already showing the right channel, so no need to refresh it
            showframe(hobj, eventdata);
        end
    end

    function sethistogramthreshold(hobj, eventdata) %#ok<INUSD>
        lfig = figure('Name','Left threshold: click where the distribution''s right tail begins','NumberTitle','off');
        L = LEFT(frame);
        hist(L(:), min(L(:)):10:max(L(:)));
        [x, y] = ginput(1); %#ok<NASGU>
        leftthreshold = x;
        if isnan(leftthreshold) || leftthreshold < 0
            leftthreshold = 0;
        end
        set(handles.leftthresholdbox, 'String', num2str(leftthreshold));
        close(lfig);
        
        rfig = figure('Name','Right threshold: click where the distribution''s right tail begins','NumberTitle','off');
        R = RIGHT(frame);
        hist(R(:), min(R(:)):10:max(R(:)));
        [x, y] = ginput(1); %#ok<NASGU>
        rightthreshold = x;
        if isnan(rightthreshold) || rightthreshold < 0
            rightthreshold = 0;
        end
        set(handles.rightthresholdbox, 'String', num2str(rightthreshold));
        close(rfig);
    end

    %Tracking a single neuron using the mouse
    function detectmanual(hobj, eventdata)
        
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue < 4 || previouschannelvalue > 7)
            if get(handles.channelchooser, 'Value') == 1
                set(handles.channel, 'Value', 4);
				trackingleft = true;
            elseif get(handles.channelchooser, 'Value') == 2
                set(handles.channel, 'Value', 5);
				trackingleft = false;
            end
			needsrefresh = true;
		elseif previouschannelvalue == 4 || previouschannelvalue == 6
			trackingleft = true;
		else %if previouschannelvalue == 5 || previouschannelvalue == 7 
			trackingleft = false;
        end
        
        [ifrom, ito, doall] = fromto; %#ok<NASGU>

        if (get(handles.frame, 'Value') ~= ifrom) %starting from the first frame
            set(handles.frame, 'Value', ifrom);
            needsrefresh = true;
        end
        if needsrefresh
            showframe(hobj, eventdata);
        end
        
        clearselection;
        
        disableeverythingtemp;
        
		detectmanualfollow; %initializing the cursor, which has detectmanualdown as a callback function

        set(gcf,'WindowButtonMotionFcn',@detectmanualfollow);
        set(gcf,'WindowButtonUpFcn', @detectmanualup);
        
        detectpressed = false;
		firstdetectpressed = true;
        while ishandle(detectcrosshairpoint)
%            disp('drawing');
            drawnow;
            if detectpressed
				if firstdetectpressed
					maxnumberofregions = maxnumberofregions + 1;
					canselectregion = true;
					canshowneurons = true;
					set(handles.showneurons,'Value',1);
    				canadjustmeasurement = true;
					firstdetectpressed = false;
				end
                detectmanualnext(hobj, eventdata, ito);
            else
                if ishandle(detectcrosshairpoint) %making sure that if the tracking is stopped while drawnow is taking place (i.e. detectpressed is false), then we do not enter uiwait
                    uiwait;
                end
            end
        end
        
        if (maxnumberofregions > 0)
            cancalculate = true;
        end
        
        updatevisibility;
        set(handles.channel, 'Value', previouschannelvalue);
        showframe(hobj,eventdata);
    end

	function detectmanualfollow (hobj, eventdata) %#ok<INUSD>
%        disp('following');
		detectcursorlocation = get(gca,'currentpoint');
        if ~ishandle(detectcrosshairpoint)
            if correctionsearchradius > 0
                detectcrosshairleft = line([detectcursorlocation(1,1)-correctionsearchradius detectcursorlocation(1,1)-correctionsearchradius], [detectcursorlocation(1,2)-correctionsearchradius detectcursorlocation(1,2)+correctionsearchradius]);
                set(detectcrosshairleft, 'Color', 'r');
                detectcrosshairright = line([detectcursorlocation(1,1)+correctionsearchradius detectcursorlocation(1,1)+correctionsearchradius], [detectcursorlocation(1,2)-correctionsearchradius detectcursorlocation(1,2)+correctionsearchradius]);
                set(detectcrosshairright, 'Color', 'r');
                detectcrosshairtop = line([detectcursorlocation(1,1)-correctionsearchradius detectcursorlocation(1,1)+correctionsearchradius], [detectcursorlocation(1,2)-correctionsearchradius detectcursorlocation(1,2)-correctionsearchradius]);
                set(detectcrosshairtop, 'Color', 'r');
                detectcrosshairbottom = line([detectcursorlocation(1,1)-correctionsearchradius detectcursorlocation(1,1)+correctionsearchradius], [detectcursorlocation(1,2)+correctionsearchradius detectcursorlocation(1,2)+correctionsearchradius]);
                set(detectcrosshairbottom, 'Color', 'r');
            end
            detectcrosshairpoint = line([detectcursorlocation(1,1) detectcursorlocation(1,1)],[detectcursorlocation(1,2) detectcursorlocation(1,2)]);
            set(detectcrosshairpoint, 'Color', 'r');
			set(detectcrosshairpoint, 'ButtonDownFcn', @detectmanualdown);
        else
            if correctionsearchradius > 0
                set(detectcrosshairleft, 'XData', [detectcursorlocation(1,1)-correctionsearchradius detectcursorlocation(1,1)-correctionsearchradius], 'YData', [detectcursorlocation(1,2)-correctionsearchradius detectcursorlocation(1,2)+correctionsearchradius]);
                set(detectcrosshairright, 'XData', [detectcursorlocation(1,1)+correctionsearchradius detectcursorlocation(1,1)+correctionsearchradius], 'YData', [detectcursorlocation(1,2)-correctionsearchradius detectcursorlocation(1,2)+correctionsearchradius]);
                set(detectcrosshairtop, 'XData', [detectcursorlocation(1,1)-correctionsearchradius detectcursorlocation(1,1)+correctionsearchradius], 'YData', [detectcursorlocation(1,2)-correctionsearchradius detectcursorlocation(1,2)-correctionsearchradius]);
                set(detectcrosshairbottom, 'XData', [detectcursorlocation(1,1)-correctionsearchradius detectcursorlocation(1,1)+correctionsearchradius], 'YData', [detectcursorlocation(1,2)+correctionsearchradius detectcursorlocation(1,2)+correctionsearchradius]);
            end
            set(detectcrosshairpoint, 'XData', detectcursorlocation(1,1), 'YData', detectcursorlocation(1,2));
        end
        uiresume(gcf);
	end

    function detectmanualnext (hobj, eventdata, endframe)
        
%        disp('adding');
        
        if (ishandle(detectcrosshairpoint))

            frame = get(handles.frame, 'Value');
            numberofregions(frame) = numberofregions(frame) + 1;

            detectcursorlocation = get(gca,'currentpoint');
            
            %simply moving the cursor now would not work because the coming
            %showframe will replace the axes and it would disappear, so
            %instead the cursor will be recreated after the showframe

			if correctionsearchradius > 0
				% Peak correction

				if trackingleft
					correctionimage = LEFT(frame);
				else %trackingright
					correctionimage = RIGHT(frame);
				end

				% Defining limits that are not out-of-bounds
				manualpeaksearchminx = max(floor(detectcursorlocation(1,1))-correctionsearchradius, 1);
				manualpeaksearchminy = max(floor(detectcursorlocation(1,2))-correctionsearchradius, 1);
				manualpeaksearchmaxx = min(ceil(detectcursorlocation(1,1))+correctionsearchradius, subchannelsizex);
				manualpeaksearchmaxy = min(ceil(detectcursorlocation(1,2))+correctionsearchradius, subchannelsizey);
				% looks for left peak locally
				[manualpeak, manualpeaky] = max(correctionimage(manualpeaksearchminy:manualpeaksearchmaxy,manualpeaksearchminx:manualpeaksearchmaxx));
				[mabspeak, manualpeakx] = max(manualpeak); % max works on vectors so have to do it like this
				manualpeaky = manualpeaky(manualpeakx); % was a vector before, now a scalar
				manualpeakx = manualpeakx + manualpeaksearchminx - 1;
				manualpeaky = manualpeaky + manualpeaksearchminy - 1;
			else %without peak-correction we just use the cursor locations
				manualpeakx = bound(round(detectcursorlocation(1,1)), 1, subchannelsizex);
				manualpeaky = bound(round(detectcursorlocation(1,2)), 1, subchannelsizey);
			end

            leftregionx(frame,numberofregions(frame)) = manualpeakx;
            leftregiony(frame,numberofregions(frame)) = manualpeaky;
            rightregionx(frame,numberofregions(frame)) = manualpeakx;
            rightregiony(frame,numberofregions(frame)) = manualpeaky;
            if strcmpi(get(handles.zpos, 'Visible'), 'on')
                leftregionz(frame, numberofregions(frame)) = get(handles.zpos, 'Value');
                rightregionz(frame, numberofregions(frame)) = get(handles.zpos, 'Value');
            else
                leftregionz(frame, numberofregions(frame)) = 1;
                rightregionz(frame, numberofregions(frame)) = 1;
            end

            leftregionradius(frame,numberofregions(frame)) = 1;
            rightregionradius(frame,numberofregions(frame)) = 1;
            regionimportant(frame, numberofregions(frame)) = true;

            newnamestring = num2str(maxnumberofregions);
            if (size(newnamestring,2) < 5) %Const size strings enforced
                newnamestring(size(newnamestring,2)+1:5) = ones(5-size(newnamestring,2),1)*32;
            elseif (size(newnamestring,2) > 5)
                fprintf('Warning: the name of the new detected region at frame %d is too large. The new name would be %s . Truncating it to %s .\n', frame, newnamestring, newnamestring(1:5));
                newnamestring = newnamestring(1:5);
            end
            regionname(frame,numberofregions(frame),:) = newnamestring;

            if frame == endframe %round(str2double(get(handles.applyto, 'String')))
                detectmanualstop(hobj, eventdata);
            else
               frame = frame + 1;
               set(handles.frame, 'Value', frame);
               showframe;
               %because showframe replaces the plot, we now have to recreate the cursor
               detectmanualfollow(hobj, eventdata);
            end
        else
            fprintf('Warning: cursor unexpectedly disappeared during manual tracking. Stopping manual tracking.\n');
            detectmanualstop(hobj, eventdata);
        end
    end

    function detectmanualdown (hobj, eventdata)
%        disp('button pressed');
        if strcmpi(get(gcf, 'selectiontype'), 'alt') == 1 %with a right click, it stops the tracking
            detectmanualstop(hobj, eventdata);
        else %with any other click, e.g. left click, it moves to the next frame and continues moving forwards in frames until the button is released
            detectpressed = true;
            uiresume(gcf);
        end
    end

    function detectmanualstop (hobj, eventdata)
%        disp('stopping');
        set(gcf, 'windowButtonMotionFcn', '');
        set(gcf, 'WindowButtonUpFcn', '');
        detectpressed = false; %forcing immediate stopping by forcing exiting of the parent loop
        if ishandle(detectcrosshairpoint)
            delete(detectcrosshairpoint);
        end
        if ishandle(detectcrosshairleft)
            delete(detectcrosshairleft);
        end
        if ishandle(detectcrosshairright)
            delete(detectcrosshairright);
        end
        if ishandle(detectcrosshairtop)
            delete(detectcrosshairtop);
        end
        if ishandle(detectcrosshairbottom)
            delete(detectcrosshairbottom);
        end
        showframe(hobj, eventdata);
        uiresume(gcf);
    end

    function detectmanualup (hobj, eventdata) %#ok<INUSD>
%        disp('button released');
        detectpressed = false;
    end

    %Detecting a single region quickly
    function detectsingle(hobj, eventdata)
        
        showframe;
        
        set(controlmanipulate, 'Enable', 'off');
        set(handles.load, 'Enable', 'off');
        set(controlcrop, 'Enable', 'off');
        set(controlsetalignment, 'Enable', 'off');
        set(controldetect,'Enable','off');
        set(controlcalculate, 'Enable', 'off');
        set(handles.readspeed, 'Enable', 'off');
        switchbackground;
        switchforeground;
        
        numberframeignored = 0;
        numberskipped = 0;
        numbercic = 0; %clock-induced charge, i.e. bad (hot) pixel appears at random locations, so if the region in the next frame is too far away from the previous position, we can assume it's CIC and skip it
        
        waithandle = waitbar(0,'Single-neuron detection...','Name','Processing','CreateCancelBtn', 'delete(gcbf)');

        speedthreshold = str2double(get(handles.speedthresholdbox, 'String'));
        withinframelimit = str2double(get(handles.withinframethresholdbox,'String'));
        
        [ifrom, ito, doall] = fromto; %#ok<NASGU>
        
        addednewregion = false;
        
        if fileformat == CONST_FILEFORMAT_BIOFORMATS && speedthreshold > 0 && false %changeme: currently disabled
            onlyreadlocally = true;
        else
            onlyreadlocally = false;
        end
        previouslx = NaN;
        previously = NaN;
        previousrx = NaN;
        previousry = NaN;
        
        for i=ifrom:ito

            if ishandle(waithandle)
                if mod(i, waitbarfps) == 0 || (exist('nf1', 'var') == 1 && nf1/nf >= waitbarfps)
                    waitbar(0.0+1.0*i/nf,waithandle);
                end
            else
                ito = i-1; %the last frame that was processed is the one before the current (if it exists)
                break;
            end            

            if ~onlyreadlocally || isnan(previousrx) || isnan(previousry) || isnan(previouslx) || isnan(previously)
                if (rightthreshold == 0 && leftthreshold == 0) || (leftthreshold > 0 && rightthreshold > 0) %cache only if we need both channels
                    cachesubimages(i);
                end
            end
            
            leftpeakx = NaN;
            leftpeaky = NaN;
            rightpeakx = NaN;
            rightpeaky = NaN;

            if (rightthreshold > 0 || leftthreshold == 0) %get the peak in the right channel only if we're going to use it
                xstarttoread = 1;
                ystarttoread = 1;
                if isnan(previousrx) || isnan(previousry) || ~onlyreadlocally
                    rightframenow = RIGHT(i);
                    correspondingareastoexclude = excludedarea;
                else
                    [xstarttoread, ystarttoread, xsizetoread, ysizetoread, rxwherenow, rywherenow] = croppedcoordinates(previousrx, previousry, speedthreshold);
                    rightframenow = readframe(i, 2, [], xstarttoread, ystarttoread, xsizetoread, ysizetoread);
                    correspondingareastoexclude = excludedarea(ystarttoread:ystarttoread+ysizetoread-1, xstarttoread:xstarttoread+xsizetoread-1);
                end
                if gaussianx > 0 %If using filters
    				rightframenow = imfilter(rightframenow, gaussianfilter);
                end
                rightframenow(correspondingareastoexclude) = NaN;
                [rightpeak, rightpeaky] = max(rightframenow);
                [rabspeak, rightpeakx] = max(rightpeak); % max works on vectors so have to do it like this
                rightpeaky = rightpeaky(rightpeakx); % was a vector before, now a scalar
                rightpeakx = rightpeakx + xstarttoread - 1;
                rightpeaky = rightpeaky + ystarttoread - 1;
            end
            
            if (leftthreshold > 0 || rightthreshold == 0) %get the peak in the left channel only if we're going to use it
                xstarttoread = 1;
                ystarttoread = 1;
                if isnan(previouslx) || isnan(previously) || ~onlyreadlocally
                    leftframenow = LEFT(i);
                    correspondingareastoexclude = excludedarea;
                else
                    [xstarttoread, ystarttoread, xsizetoread, ysizetoread, lxwherenow, lywherenow] = croppedcoordinates(previouslx, previously, speedthreshold);
                    leftframenow = readframe(i, 1, [], xstarttoread, ystarttoread, xsizetoread, ysizetoread);
                    correspondingareastoexclude = excludedarea(ystarttoread:ystarttoread+ysizetoread-1, xstarttoread:xstarttoread+xsizetoread-1);
                end
                if gaussianx > 0 %If using filters
    				leftframenow = imfilter(leftframenow, gaussianfilter);
                end
                leftframenow(correspondingareastoexclude) = NaN;
                [leftpeak, leftpeaky] = max(leftframenow);
                [labspeak, leftpeakx] = max(leftpeak); % max works on vectors so have to do it like this
                leftpeaky = leftpeaky(leftpeakx); % was a vector before, now a scalar
                leftpeakx = leftpeakx + xstarttoread - 1;
                leftpeaky = leftpeaky + ystarttoread - 1;
            end
            
            if isnan(leftpeakx) || isnan(leftpeaky)
                leftpeakx = rightpeakx;
                leftpeaky = rightpeaky;
            end
            
            if isnan(rightpeakx) || isnan(rightpeaky)
                rightpeakx = leftpeakx;
                rightpeaky = leftpeaky;
            end
            
            %if the currently detected peak turns out to be not appropriate for whatever reason (speed, intensity, etc), then we're going into the next frame without previous knowledge
            previouslx = NaN;
            previously = NaN;
            previousrx = NaN;
            previousry = NaN;
            
            %Only assign a region if the peak is larger than the threshold
            %so that no regions will be assigned in empty frames
            if ~( (leftthreshold > 0 && labspeak < leftthreshold) || (rightthreshold > 0 && rabspeak < rightthreshold))
                
                if withinframelimit > 0 && leftthreshold > 0 && rightthreshold > 0
                    %Checking if the assignment error exceeds the limit for any
                    %of the regions. If so, the assignment is almost certainly
                    %erroneous, and trying to correct for it would be difficult
                    %and dangerous. Therefore, in this case, no assignment is
                    %made for the focal frame
                    if hypot(leftpeakx-rightpeakx, leftpeaky-rightpeaky) > withinframelimit
                        %fprintf('Warning: within-frame alignment error threshold exceeded in frame %d. No regions will be assigned in this frame.\n', i);
                        numberframeignored = numberframeignored + 1;
                        continue; %jump to next i
                    end
                end
                
                if (speedthreshold > 0 && i > 1 && numberofregions(i-1) > 0)
                    if hypot(leftpeakx-leftregionx(i-1,1), leftpeaky-leftregiony(i-1,1)) > speedthreshold || hypot(rightpeakx-rightregionx(i-1,1), rightpeaky-rightregiony(i-1,1)) > speedthreshold
                        %fprintf('Warning: across-frame speed threshold exceeded in frame %d. No regions will be assigned in this frame.\n', i);
                        numbercic = numbercic + 1;
                        continue;
                    end
                end

                if ~addednewregion
                    addednewregion = true;
                    maxnumberofregions = maxnumberofregions + 1;
                    canselectregion = true;
                    set(controlselectregion,'Enable','on'); %now that there is a region detected, enable ability to select regions
                    canshowneurons = true;
                    set(handles.showneurons,'Enable','on','Value',1);
                    canadjustmeasurement = true;
                    set(controladjustmeasurement,'Enable','on');
                    switchforeground;
                    switchbackground;
                    newnamestring = num2str(maxnumberofregions);
                    if (size(newnamestring,2) < 5) %Const size strings enforced
                        newnamestring(size(newnamestring,2)+1:5) = ones(5-size(newnamestring,2),1)*32;
                    elseif (size(newnamestring,2) > 5)
                        fprintf('Error: name of the new detected region at frame %d is too long (%s).\n', i, newnamestring);
                    end
                end
                
                numberofregions(i) = numberofregions(i)+1;
                if (leftthreshold == 0 && rightthreshold > 0) %assign position based on the right channel
                    leftregionx(i,numberofregions(i)) = rightpeakx;
                    leftregiony(i,numberofregions(i)) = rightpeaky;
                    rightregionx(i,numberofregions(i)) = rightpeakx;
                    rightregiony(i,numberofregions(i)) = rightpeaky;
                elseif (rightthreshold == 0 && leftthreshold > 0) %assign position based on the left channel
                    leftregionx(i,numberofregions(i)) = leftpeakx;
                    leftregiony(i,numberofregions(i)) = leftpeaky;
                    rightregionx(i,numberofregions(i)) = leftpeakx;
                    rightregiony(i,numberofregions(i)) = leftpeaky;
                else %assign position normally
                    leftregionx(i,numberofregions(i)) = leftpeakx;
                    leftregiony(i,numberofregions(i)) = leftpeaky;
                    rightregionx(i,numberofregions(i)) = rightpeakx;
                    rightregiony(i,numberofregions(i)) = rightpeaky;
                end
                if strcmpi(get(handles.zpos, 'Visible'), 'on')
                    leftregionz(i, numberofregions(i)) = get(handles.zpos, 'Value');
                    rightregionz(i, numberofregions(i)) = get(handles.zpos, 'Value');
                else
                    leftregionz(i, numberofregions(i)) = 1;
                    rightregionz(i, numberofregions(i)) = 1;
                end
                leftregionradius(i,numberofregions(i)) = 1;
                rightregionradius(i,numberofregions(i)) = 1;
                regionimportant(i, numberofregions(i)) = true;
                regionname(i,numberofregions(i),:) = newnamestring;
%                regionname(i,numberofregions(i),:) = '1    '; %regionname(previousframe, 1, :);

                %the peak turned out to be usable, so we're remembering it for the next frame
                previouslx = leftpeakx;
                previously = leftpeaky;
                previousrx = rightpeakx;
                previousry = rightpeaky;
                
            else
                numberskipped = numberskipped + 1;
            end
        end
        
        frameslookedat = ito-ifrom+1;
        if frameslookedat > 0 %If the user cancels the neuron detection even before the first frame is processed, don't display results and don't divide by zero
            fprintf('Regions of interest were found in %d of %d frames altogether (%3.1f%%).\n',frameslookedat-numberskipped, frameslookedat, (frameslookedat-numberskipped)/frameslookedat*100.0);
            if str2double(get(handles.withinframethresholdbox,'String')) ~= 0 && leftthreshold > 0 && rightthreshold > 0
                fprintf('Region creation was suspended due to unreasonable across-channel assignment costs in %d of %d frames (%3.1f%%).\n', numberframeignored, frameslookedat, numberframeignored/frameslookedat*100.0);
            end
            if speedthreshold > 0
                fprintf('Region creation was suspended due to unreasonable perceived region speeds in %d of %d frames (%3.1f%%).\n', numbercic, frameslookedat, numbercic/frameslookedat*100.0);
            end
        end

        if ishandle(waithandle)
            close(waithandle);
        end
        
        if (maxnumberofregions > 0)
            cancalculate = true;
        end
        
        updatevisibility;
        showframe(hobj,eventdata);
        
    end

    function detectheuristic (hobj, eventdata)
        
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue < 4 || previouschannelvalue > 7)
            if get(handles.channelchooser, 'Value') == 1
                set(handles.channel, 'Value', 4);
				trackingleft = true;
            elseif get(handles.channelchooser, 'Value') == 2
                set(handles.channel, 'Value', 5);
				trackingleft = false;
            end
			needsrefresh = true;
		elseif previouschannelvalue == 4 || previouschannelvalue == 6
			trackingleft = true;
		else %if previouschannelvalue == 5 || previouschannelvalue == 7 
			trackingleft = false;
        end
        if needsrefresh
            showframe(hobj, eventdata);
        end
        
        clearselection;
        disableeverythingtemp;
        
        maxnumberofregions = maxnumberofregions + 1;
        newnamestring = num2str(maxnumberofregions);
        if (size(newnamestring,2) < 5) %Const size strings enforced
            newnamestring(size(newnamestring,2)+1:5) = ones(5-size(newnamestring,2),1)*32;
        elseif (size(newnamestring,2) > 5)
            fprintf('Warning: the name of the new detected region at frame %d is too large. The new name would be %s . Truncating it to %s .\n', frame, newnamestring, newnamestring(1:5));
            newnamestring = newnamestring(1:5);
        end
        
        speedthreshold = str2double(get(handles.speedthresholdbox, 'String'));
        searchradius = round(str2double(get(handles.correctionsearchradius,'String')));
        
        currentintensity = NaN;
        x = NaN;
        y = NaN;
        previousintensity = NaN;
        previousx = NaN;
        previousy = NaN;
        previoussinglex = NaN;
        previoussingley = NaN;
        
        CONST_THRESHOLD_INCREASE_MULTIPLIER = 1.05; %we multiply the threshold by this value when we want to increase the threshold to detect more regions, or divide by it when we want to detect fewer regions
        
        confusionforcedclick = false; %is we are not confident in tracking the neuron in the current frame, we will set this to true, which will force a click by the user giving us the coordinates of the neuron in the current frame
        clicktype = 'normal';
        
        [ifrom, ito, doall] = fromto; %#ok<NASGU>
        
        waithandle = NaN; %we're necessarily starting with a forced mouseclick so there's no need to show waitbar immediately, only after the mouseclick, but we do need to initialize the variable
        
        i = ifrom;
        while i<=ito %we're doing it like this instead of a for cycle because we may not always want to grow i by 1 at the end of each cycle (e.g. when we're confused about where the neuron is and we want to ask user input in the same frame)
            
            if trackingleft
                framenow = LEFT(i);
            else
                framenow = RIGHT(i);
            end
            if gaussianx > 0 %If using filters
                blurred = imfilter(framenow, gaussianfilter); %blur it a bit so that we get continuous areas
            else
                blurred = framenow;
            end
            
            if isnan(previousintensity) || confusionforcedclick %if we don't have a previous reference, or the a user-click has been forced
                set(handles.frame, 'Value', i);
                if ishandle(waithandle)
                    delete(waithandle);
                end
                showframe;
                [x, y, clicktype] = zinput('crosshair', 'radius', min([subchannelsizex subchannelsizey])/20);
                waithandle = waitbar(0,'Tracking...','Name','Processing', 'CreateCancelBtn', 'delete(gcbf)');
                if ~strcmpi(clicktype, 'alt')
                    x = round(x);
                    y = round(y);
                    peakminx = max([round(x)-1 1]);
                    peakmaxx = min([round(x)+1 subchannelsizex]);
                    peakminy = max([round(y)-1 1]);
                    peakmaxy = min([round(y)+1 subchannelsizey]);
                    currentintensity = mean(mean(blurred(peakminy:peakmaxy, peakminx:peakmaxx)));
                    confusionforcedclick = false;
                else %stopping the tracking entirely if the user clicked with the right mouse button
                    break;
                end
            else %tracking
                
                if ishandle(waithandle)
                    if mod(i, waitbarfps) == 0
                        waitbar(i/nf, waithandle);
                    end
                else
                    break; %if the waitbar doesn't exist because cancel or the X in the corner were clicked, then we should stop tracking
                end
                
                xmin = max([previousx-searchradius, 1]);
                xmax = min([previousx+searchradius, subchannelsizex]);
                ymin = max([previousy-searchradius, 1]);
                ymax = min([previousy+searchradius, subchannelsizey]);
                
                areatolookat = blurred(ymin:ymax, xmin:xmax);
                %figure; imshow(areatolookat, []); colormap(jet); title(num2str(i));
                currentthreshold = previousintensity;
                
                previousgoodcentroidsfound = NaN;
                
                thresholdtrials = 0;
                
                while true %we're trying different thresholds here, and if we find something that works, we'll break out of the loop
                    
                    thresholdtrials = thresholdtrials + 1;
                
                    thresholded = im2bw(areatolookat/65535,currentthreshold/65535); %mark pixels above threshold as 1
                    labelled = logical(thresholded);
                    if verLessThan('matlab', '7.8')
                        labelled = bwlabeln(labelled);
                    end
                    
                    if sum(labelled(:)) == numel(labelled) %everything got thresholded. Most likely the reason why there's no easy way to distinguish between two neurons is because there's only one neuron in the areatolookat
                        %so we'll try to see if the brightest point is a good candidate for a neuron
                        [peakvector, peakyvector] = max(areatolookat);
                        [abspeak, peakx] = max(peakvector); % max works on vectors so have to do it like this
                        peaky = peakyvector(peakx); % was a vector before, now a scalar
                        peakminx = max([round(peakx)-1 1]);
                        peakmaxx = min([round(peakx)+1 size(areatolookat, 2)]);
                        peakminy = max([round(peaky)-1 1]);
                        peakmaxy = min([round(peaky)+1 size(areatolookat, 1)]);
                        currentintensity = mean(mean(areatolookat(peakminy:peakmaxy, peakminx:peakmaxx)));
                        x = round(peakx + xmin - 1);
                        y = round(peaky + ymin - 1);
                        if currentintensity / previousintensity < 0.67 || currentintensity / previousintensity > 1.5 || realsqrt((previousx - x)^2 + (previousy - y)^2) > speedthreshold %check if it makes sense compared to what we saw in the previous frame, and discard it if not
                            x = NaN;
                            y = NaN;
                            currentintensity = NaN;
                            confusionforcedclick = true;
                        end
                        break;
                    end
                    
                    props = regionprops(labelled,'Centroid','Area'); %get centroid and area size for each region of interest %KEPT LIKE THIS FOR COMPATIBILITY REASONS
                    centroids = vertcat(props.Centroid);
                    if ~isempty(centroids)
                        centroidsx = centroids(:, 1);
                        centroidsy = centroids(:, 2);
                        takeout = vertcat(props.Area) < minimalneuronsize;
                        centroidsx = centroidsx(~takeout);
                        centroidsy = centroidsy(~takeout);
                        centroidsinframex = centroidsx + xmin - 1;
                        centroidsinframey = centroidsy + ymin - 1;
                        centroiddistance = realsqrt((previousx - centroidsinframex).^2 + (previousy - centroidsinframey).^2);
                    else
                        centroidsx = [];
                        centroidsy = [];
                        centroiddistance = [];
                        centroidsinframex = [];
                        centroidsinframey = [];
                    end
                    centroidsfound = numel(centroidsx);
                    goodcentroids = ~ ( round(centroidsx-1) < 1 | round(centroidsx+1) > size(areatolookat, 2) | round(centroidsy-1) < 1 | round(centroidsy+1) > size(areatolookat, 1) | centroiddistance > speedthreshold );
                    goodcentroidsfound = sum(goodcentroids);
                    
                    if centroidsfound > 1 %we need to decide between using one of two or more centriods to follow
                        
                        if previousgoodcentroidsfound <= 1 %if we just arrived at the right thresholding level (previously there was <= 1 good centroids and now there's > 1 centroids
                            if ~isnan(previoussinglex) && ~isnan(previoussingley) %if a previous single thresholded region exists (with a higher threshold) exists, it should give more accurate centroid coordinates than this lower threshold one, so we should replace one of the current centroids with the previous single one
                                distancefromhigherthreshold = NaN(1, numel(centroidsx));
                                for j=1:numel(centroidsx)
                                    distancefromhigherthreshold(j) = realsqrt((previoussinglex - centroidsx(j))^2 + (previoussingley - centroidsy(j))^2);
                                end
                                [toreplacedistance, toreplaceindex] = min(distancefromhigherthreshold);
                                centroidsx(toreplaceindex) = previoussinglex;
                                centroidsy(toreplaceindex) = previoussingley;
                                centroidsinframex = centroidsx + xmin - 1;
                                centroidsinframey = centroidsy + ymin - 1;
                            end
                            peakintensity = NaN(1, numel(centroidsx));
                            heuristicdistance = NaN(1, numel(centroidsx));
                            heuristicintensity = NaN(1, numel(centroidsx));
                            for j=1:numel(centroidsx)
                                peakminx = max([round(centroidsx(j))-1 1]);
                                peakmaxx = min([round(centroidsx(j))+1 size(areatolookat, 2)]);
                                peakminy = max([round(centroidsy(j))-1 1]);
                                peakmaxy = min([round(centroidsy(j))+1 size(areatolookat, 1)]);
                                peakintensity(j) = mean(mean(areatolookat(peakminy:peakmaxy, peakminx:peakmaxx)));
                                heuristicdistance(j) = realsqrt((previousx - centroidsinframex(j))^2 + (previousy - centroidsinframey(j))^2);
                                heuristicintensity(j) = peakintensity(j)/previousintensity;
                                if heuristicintensity(j) < 1
                                    heuristicintensity(j) = 1.0 / heuristicintensity(j);
                                end
                                if heuristicdistance(j) > speedthreshold
                                    heuristicdistance(j) = NaN;
                                    heuristicintensity(j) = NaN;
                                end
                            end
                            
                            [sortedintensity, sortedintensityindices] = sort(heuristicintensity, 'ascend');
                            [sorteddistance, sorteddistanceindices] = sort(heuristicdistance, 'ascend');
                            
                            if sortedintensity(2) / sortedintensity(1) > 1.1 || (~isnan(sortedintensity(1)) && isnan(sortedintensity(2)))
                                intensitysignificant = true;
                            else
                                intensitysignificant = false;
                            end
                            
                            if sorteddistance(2) / sorteddistance(1) > 2.0 || (~isnan(sorteddistance(1)) && isnan(sorteddistance(2)))
                                distancesignificant = true;
                            else
                                distancesignificant = false;
                            end
                            
                            if sortedintensityindices(1) == sorteddistanceindices(1)
                                whichbest = sortedintensityindices(1);
                            elseif intensitysignificant && ~distancesignificant
                                whichbest = sortedintensityindices(1);
                            elseif ~intensitysignificant && distancesignificant
                                whichbest = sorteddistanceindices(1);
                            elseif ~intensitysignificant && ~distancesignificant && sorteddistance(2) - sorteddistance(1) < 2 %if there's no significant difference between the two best regions AND they're very very close, then it doesn't matter which one we track because most likely they're the same neuron, except broken down into two regions for some reason
                                whichbest = sortedintensityindices(1);
                            else
                                whichbest = NaN;
                            end
                            
                            if ~isnan(whichbest) && ~isnan(heuristicintensity(whichbest)) && ~isnan(heuristicdistance(whichbest))
                                x = round(centroidsinframex(whichbest));
                                y = round(centroidsinframey(whichbest));
                                currentintensity = peakintensity(whichbest);
                            else
                                x = NaN;
                                y = NaN;
                                currentintensity = NaN;
                                confusionforcedclick = true;
                            end
                            
                            break;
                        else
                            currentthreshold = currentthreshold * CONST_THRESHOLD_INCREASE_MULTIPLIER;
                        end
                    elseif centroidsfound <= 1
                        currentthreshold = currentthreshold / CONST_THRESHOLD_INCREASE_MULTIPLIER;
                    else
                        fprintf(2, 'Error: unreasonable number of centroids found in frame %d.\n', i);
                        break;
                    end
                    
                    previousgoodcentroidsfound = goodcentroidsfound;
                    
                    if goodcentroidsfound == 1
                        previoussinglex = centroidsx(find(goodcentroids, 1));
                        previoussingley = centroidsy(find(goodcentroids, 1));
                    else
                        previoussinglex = NaN;
                        previoussingley = NaN;
                    end
                    
                end
                
            end
            
            if ~isnan(x) && ~isnan(y) && ~isnan(currentintensity)
                
                numberofregions(i) = numberofregions(i)+1;
                leftregionx(i,numberofregions(i)) = x;
                leftregiony(i,numberofregions(i)) = y;
                rightregionx(i,numberofregions(i)) = x;
                rightregiony(i,numberofregions(i)) = y;
                
                if strcmpi(get(handles.zpos, 'Visible'), 'on')
                    leftregionz(i, numberofregions(i)) = get(handles.zpos, 'Value');
                    rightregionz(i, numberofregions(i)) = get(handles.zpos, 'Value');
                else
                    leftregionz(i, numberofregions(i)) = 1;
                    rightregionz(i, numberofregions(i)) = 1;
                end
                
                leftregionradius(i,numberofregions(i)) = 1;
                rightregionradius(i,numberofregions(i)) = 1;
                regionimportant(i, numberofregions(i)) = true;
                regionname(i,numberofregions(i),:) = newnamestring;
                
                previousintensity = currentintensity;
                previousx = x;
                previousy = y;
                i = i + 1;
            elseif ~confusionforcedclick
                fprintf(2, 'Warning: neuron couldn''t be tracked properly in frame %d, but forcing of user-clicking did not occur.\n', frame);
                break;
            end
            
        end
        
        if ishandle(waithandle)
            delete(waithandle);
        end
        
        %We'll show the last frame that we tracked into so that the user can check if the end target is still accurate. 
        if strcmpi(clicktype, 'alt')
            frame = i; %if the user exited manually, then the frame we want to end up showing is the "current" one
        else
            frame = i-1; %if the tracking ended automatically, then i will be lastframetocheck+1 when we exit from the loop, so we need to subtract one to get the last frame where there was tracking
        end
       
        set(handles.frame, 'Value', frame);
        if (maxnumberofregions > 0)
            canselectregion = true;
            canshowneurons = true;
            cancalculate = true;
            set(handles.showneurons,'Enable','on','Value',1);
            canadjustmeasurement = true;
            switchforeground;
            switchbackground;
        end
        updatevisibility;
        set(handles.channel, 'Value', previouschannelvalue);
        showframe(hobj,eventdata);
        
    end

    function detectold(hobj,eventdata)

        set(handles.load, 'Enable', 'off');
        set(controlcrop, 'Enable', 'off');
        set(controlsetalignment, 'Enable', 'off');
        set(controldetect,'Enable','off');
        set(controlcalculate, 'Enable', 'off');
        set(controlmanipulate, 'Enable', 'off');
        set(handles.readspeed, 'Enable', 'off');
        switchbackground;
        switchforeground;
        
        waithandle = waitbar(0,'Multi-neuron detection...','Name','Processing','CreateCancelBtn', 'delete(gcbf)');
        
        numberskipped = 0;
        numberfellback = 0;
        numberforcednew = 0;
        numberframeignored = 0;

		%Specifying whether we're going to process these channels
        %Since currently the threshold is the same for all frames, using
        %index 1 to get the threshold value. If thresholds can vary, then
        %this needs to be changed so that it's checked at each i
        if leftthreshold > 0 || rightthreshold == 0
			usingleft = true;
		else
			usingleft = false;
        end
        if rightthreshold > 0 || leftthreshold == 0
			usingright = true;
		else
			usingright = false;
        end
        
        previousdisplacementx = [];
        previousdisplacementy = [];
        
        [ifrom, ito, doall] = fromto; %#ok<NASGU>
        
        speedthreshold = str2double(get(handles.speedthresholdbox, 'String'));
        
        for i=ifrom:ito

            if ishandle(waithandle)
                if mod(i, waitbarfps) == 0 || (exist('nf1', 'var') == 1 && nf1/nf >= waitbarfps)
                    waitbar(0.0+1.0*i/nf,waithandle);
                end
            else
                ito = i-1; %the last frame that was processed is the one before the current (if it exists)
                break;
            end

			if (usingleft && usingright) %cache only if we need both channels
            	cachesubimages(i);
			end

			if (usingright) %get the regions in the right channel only if we're going to use it
				rightframenow = RIGHT(i);
	
                if gaussianx > 0 %If using filters
    				rblurred = imfilter(rightframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                else
                    rblurred = rightframenow;
                end
				rlogical = im2bw(rblurred/65535,rightthreshold/65535); %mark pixels above threshold as 1

				rlabel = logical(rlogical);
                if verLessThan('matlab', '7.8')
                    rlabel = bwlabel(rlabel);
                end
				
				rprops = regionprops(rlabel,'Centroid','Area'); %get centroid and area size for each region of interest %KEPT LIKE THIS FOR COMPATIBILITY REASONS
				rprops = rprops(vertcat(rprops.Area) >= minimalneuronsize); % only consider it a neuron if it's larger than a minimum value
				rcent = vertcat(rprops.Centroid);
				rnumber = size(rcent,1);
				
                if (rnumber == 0) %nothing detected in right channel, skip detection in left, go to the next frame
					%disp('skipped frame:');
					%disp(i);
					numberskipped = numberskipped + 1;
					continue;
                end
            else
                rnumber = 0;
			end
            
			if (usingleft) %get the regions in the left channel only if we're going to use it
				leftframenow = LEFT(i);

                if gaussianx > 0 %If using filters
    				lblurred = imfilter(leftframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                else
                    lblurred = leftframenow;
                end
				llogical = im2bw(lblurred/65535,leftthreshold/65535); %mark pixels above threshold as 1
	
				llabel = logical(llogical);
                if verLessThan('matlab', '7.8')
                    llabel = bwlabel(llabel);
                end
				
				lprops = regionprops(llabel,'Centroid','Area'); %get centroid and area size for each region of interest %KEPT LIKE THIS FOR COMPATIBILITY REASONS
				lprops = lprops(vertcat(lprops.Area) >= minimalneuronsize); % only consider it a neuron if it's larger than a minimum value
				lcent = vertcat(lprops.Centroid);
				lnumber = size(lcent,1);
                if (lnumber == 0) %nothing detected in left channel, go to the next frame
					%disp('skipped frame:');
					%disp(i);
					numberskipped = numberskipped + 1;
					continue;
                end
            else
                lnumber = 0;
			end


			maxnumber = max(lnumber, rnumber); %number of regions at most (will probably have to discard some)

			% Peak-correction (locating the nearest peak within a
			% certain radius to get the neuron's real location more
			% accurately
			
			leftpeakxk = NaN;
			leftpeakyk = NaN;
			leftpeakradius = NaN;
			rightpeakxk = NaN;
			rightpeakyk = NaN;
			rightpeakradius = NaN;
			
            for k=1:maxnumber
				if usingleft
					if (k <= lnumber)
						if correctionsearchradius > 0
							% defining the limits of the search rectangle, making sure
							% that it doesn't get out of bounds
							leftpeaksearchminx = max(floor(lcent(k,1))-correctionsearchradius, 1);
							leftpeaksearchminy = max(floor(lcent(k,2))-correctionsearchradius, 1);
							leftpeaksearchmaxx = min(size(leftframenow,2), ceil(lcent(k,1))+correctionsearchradius);
							leftpeaksearchmaxy = min(size(leftframenow,1), ceil(lcent(k,2))+correctionsearchradius);
		
							% looking for left peak locally
							[leftpeak, leftpeaky] = max(leftframenow(leftpeaksearchminy:leftpeaksearchmaxy,leftpeaksearchminx:leftpeaksearchmaxx));
							[labspeak, leftpeakx] = max(leftpeak); % max works on vectors so have to do it like this
							leftpeaky = leftpeaky(leftpeakx); % was a vector before, now a scalar
							if isempty(leftpeakx)
								disp('Error: empty leftpeakx!');
								disp(leftpeakx);
								disp(leftpeaky);
								disp(leftpeaksearchminx);
								disp(leftpeaksearchmaxx);
								disp(leftpeaksearchminy);
								disp(leftpeaksearchmaxy);
							end
							%storing peaks in local variable. needs to be paired
							%with corresponding right peak before it is stored globally
							leftpeakxk(k) = leftpeakx + leftpeaksearchminx - 1; 
							leftpeakyk(k) = leftpeaky + leftpeaksearchminy - 1;
							leftpeakradius(k) = sqrt(lprops(k).Area);
						else %without peak correction we just store the centroid coordinates
							leftpeakxk(k) = round(lcent(k,1));
							leftpeakyk(k) = round(lcent(k,2));
							leftpeakradius(k) = sqrt(lprops(k).Area);
						end
					else %if there are more regions detected in the other channel, fill this up with dummy values so that the number of regions in the two channels is effectively the same (although these dummy regions will never be paired)
						leftpeakxk(k) = inf;
						leftpeakyk(k) = inf;
						leftpeakradius(k) = 0;
					end
				end
			
				if usingright
					if (k <= rnumber)
						if correctionsearchradius > 0
							% defining the limits of the search rectangle, making sure
							% that it doesn't get out of bounds
							rightpeaksearchminx = max(floor(rcent(k,1))-correctionsearchradius, 1);
							rightpeaksearchminy = max(floor(rcent(k,2))-correctionsearchradius, 1);
							rightpeaksearchmaxx = min(size(rightframenow,2), ceil(rcent(k,1))+correctionsearchradius);
							rightpeaksearchmaxy = min(size(rightframenow,1), ceil(rcent(k,2))+correctionsearchradius);
		
							% looking for the right peak locally
							[rightpeak, rightpeaky] = max(rightframenow(rightpeaksearchminy:rightpeaksearchmaxy,rightpeaksearchminx:rightpeaksearchmaxx));
							[rabspeak, rightpeakx] = max(rightpeak); % max works on vectors so have to do it like this
							rightpeaky = rightpeaky(rightpeakx); % was a vector before, now a scalar
							if isempty(rightpeakx)
								disp('Error: empty rightpeakx!');
								disp(rightpeakx);
								disp(rightpeaky);
								disp(rightpeaksearchminx);
								disp(rightpeaksearchmaxx);
								disp(rightpeaksearchminy);
								disp(rightpeaksearchmaxy);
							end
							%storing peaks in local variable. needs to be paired
							%with corresponding left peak before it is stored globally
							rightpeakxk(k) = rightpeakx + rightpeaksearchminx - 1;
							rightpeakyk(k) = rightpeaky + rightpeaksearchminy - 1;
							rightpeakradius(k) = sqrt(rprops(k).Area);
						else %without peak correction we just store the centroid coordinates
							rightpeakxk(k) = round(rcent(k,1));
							rightpeakyk(k) = round(rcent(k,2));
							rightpeakradius(k) = sqrt(rprops(k).Area);
						end
					else %if there are more regions detected in the other channel, fill this up with dummy values so that the number of regions in the two channels is effectively the same (although these dummy regions will never be paired) 
						rightpeakxk(k) = inf;
						rightpeakyk(k) = inf;
						rightpeakradius(k) = 0;
					end
				end
            end
			
            if usingleft && usingright
				%Within-frame neuron identity assignment
				
				%Calculates squared distances across all pairs (left-right channel bipartite)
				costmatrix = Inf(lnumber, rnumber);
                for j=1:lnumber
                    for k=1:rnumber
						costmatrix(j,k) = (leftpeakxk(j)-rightpeakxk(k))^2 + ((leftpeakyk(j)+rightdisplacementy)-rightpeakyk(k))^2; %we want squared distance here, so avoiding the hypot function
                    end
                end
                
				assignment = assignmentoptimal(costmatrix); %Solving the within-frame assignment problem using the Hungarian algorithm
				
				%Checking if the assignment error exceeds the limit for any
				%of the regions. If so, the assignment is almost certainly
				%erroneous, and trying to correct for it would be difficult
				%and dangerous. Therefore, in this case, no assignment is
				%made for the focal frame
				withinframelimit = str2double(get(handles.withinframethresholdbox,'String'));
				if (withinframelimit) > 0
					jumptonexti = false;
					for j=1:size(assignment,1)
						if (assignment(j,1) ~= 0)
							%if (sqrt((leftpeakxk(j))-rightpeakxk(assignment(j,1)))^2+(leftpeakyk(j)-rightpeakyk(assignment(j,1)))^2) > withinframelimit
                            if hypot(leftpeakxk(j)-rightpeakxk(assignment(j,1)), leftpeakyk(j)-rightpeakyk(assignment(j,1))) > withinframelimit
								% fprintf('Warning: within-frame alignment error threshold exceeded in frame %d. No regions will be assigned in this frame.\n', i);
								clear rightpeakxk;
								clear rightpeakyk;
								clear rightpeakradius;
								clear leftpeakxk;
								clear leftpeakyk;
								clear leftpeakradius;
								numberframeignored = numberframeignored + 1;
								jumptonexti = true;
								break; %break the cycle going through the regions and jump to the next frame
                            end
						end
					end
					if jumptonexti
						continue;
					end
				end
	
				numberofnewregions = 0;
				newleftregionx = zeros(maxnumberofregions + size(assignment,1),1);
				newleftregiony = zeros(maxnumberofregions + size(assignment,1),1);
				newrightregionx = zeros(maxnumberofregions + size(assignment,1),1);
				newrightregiony = zeros(maxnumberofregions + size(assignment,1),1);
				newleftregionradius = zeros(maxnumberofregions + size(assignment,1),1);
				newrightregionradius = zeros(maxnumberofregions + size(assignment,1),1);
				for j=1:size(assignment,1)
					if (assignment(j,1) ~= 0)
						numberofnewregions = numberofnewregions+1;
						newleftregionx(numberofnewregions) = leftpeakxk(j);
						newleftregiony(numberofnewregions) = leftpeakyk(j);
						newrightregionx(numberofnewregions) = rightpeakxk(assignment(j,1));
						newrightregiony(numberofnewregions) = rightpeakyk(assignment(j,1));
						newleftregionradius(numberofnewregions) = leftpeakradius(j);
						newrightregionradius(numberofnewregions) = rightpeakradius(assignment(j,1));
					end
				end

			elseif usingleft %assigning coordinates in the right channel based on the left
				
				numberofnewregions = 0;
				newleftregionx = zeros(maxnumberofregions + lnumber);
				newleftregiony = zeros(maxnumberofregions + lnumber);
				newrightregionx = zeros(maxnumberofregions + lnumber);
				newrightregiony = zeros(maxnumberofregions + lnumber);
				newleftregionradius = zeros(maxnumberofregions + lnumber);
				newrightregionradius = zeros(maxnumberofregions + lnumber);
				for j=1:lnumber
					numberofnewregions = numberofnewregions+1;
					newleftregionx(numberofnewregions) = leftpeakxk(j);
					newleftregiony(numberofnewregions) = leftpeakyk(j);
					newrightregionx(numberofnewregions) = leftpeakxk(j);
					newrightregiony(numberofnewregions) = leftpeakyk(j);
					newleftregionradius(numberofnewregions) = leftpeakradius(j);
					newrightregionradius(numberofnewregions) = leftpeakradius(j);
				end
			
			elseif usingright %assigning coordinates in the left channel based on the right

				numberofnewregions = 0;
				newleftregionx = zeros(maxnumberofregions + rnumber);
				newleftregiony = zeros(maxnumberofregions + rnumber);
				newrightregionx = zeros(maxnumberofregions + rnumber);
				newrightregiony = zeros(maxnumberofregions + rnumber);
				newleftregionradius = zeros(maxnumberofregions + rnumber);
				newrightregionradius = zeros(maxnumberofregions + rnumber);
				for j=1:rnumber
					numberofnewregions = numberofnewregions+1;
					newleftregionx(numberofnewregions) = rightpeakxk(j);
					newleftregiony(numberofnewregions) = rightpeakyk(j);
					newrightregionx(numberofnewregions) = rightpeakxk(j);
					newrightregiony(numberofnewregions) = rightpeakyk(j);
					newleftregionradius(numberofnewregions) = rightpeakradius(j);
					newrightregionradius(numberofnewregions) = rightpeakradius(j);
				end

            end
            

			%Across-frame neuron identity preservation (tracking)
			%This is based on the left channel (arbitrarily)
			
			hasbeenpaired = zeros(numberofnewregions,1); %Will have to add regions for which no assignment was made after the assignment had been made
			previousframe = i-1;
			%One intermediate frame can be blurred due to stage
			%movement. Check if we have fewer regions detected in the
			%previous frame than before, and than now, and if so, use
			%the one before the previous one as the reference frame
            if (i >= 3)
				previousregions = numberofregions(previousframe); 
				beforethatregions = numberofregions(previousframe-1);
                if (previousregions < numberofnewregions && beforethatregions > previousregions)
					previousframe = previousframe - 1;
					previousregions = beforethatregions;
                    %Do not take into account displacements if it's not based on the previous frame, because if there is a two frame distance, it's probably due to stage movement, which would no longer be relevant one frame later and just mess things up.
                    previousdisplacementx = [];
                    previousdisplacementy = [];
                end
			elseif (i == 2)
				previousregions = numberofregions(previousframe);
			else
				previousregions = 0;
            end

            if (i>1 && previousregions > 0)
                
				costmatrix = Inf(numberofnewregions, numberofregions(previousframe));
                for j=1:numberofnewregions
                    for k=1:numberofregions(previousframe)
                        if (leftregionx(previousframe,k) == 0 || leftregiony(previousframe,k) == 0)
							costmatrix(j,k) = Inf;
                            fprintf('Warning: null region in frame %d.\n', i);
						else
							%Checking if regions in the previous
							%frame have corresponding regions in
							%the current frame already (which have
							%already been named and assigned), in which
							%case they should not be available as a
							%potential match for the new regions
                            %This is normal in case multi-neuron detection
                            %is performed after some neurons have already
                            %been detected, named and assigned.
							regionalreadyassigned = false;
                            for l=1:numberofregions(i)
								if (strcmp(char(regionname(i,l,:)), char(regionname(previousframe, k, :))) == 1)
									regionalreadyassigned = true;
									%fprintf('Warning: region already exists in frame %d\n', i);
									break;
								end
                            end
                            if (~regionalreadyassigned)
								%Using the worm-displacement correction
								%calculated above
                                if ~isempty(previousdisplacementx) && ~isnan(previousdisplacementx(k))
                                    previousregionxdisplaced = leftregionx(previousframe,k)+previousdisplacementx(k);
                                    previousregionydisplaced = leftregiony(previousframe,k)+previousdisplacementy(k);
                                else
                                    previousregionxdisplaced = leftregionx(previousframe,k);
                                    previousregionydisplaced = leftregiony(previousframe,k);
                                end
                                costmatrix(j,k) = (newleftregionx(j)-previousregionxdisplaced)^2 + (newleftregiony(j)-previousregionydisplaced)^2; %we want squared distance
%								costmatrix(j,k) = (newleftregionx(j)-(leftregionx(previousframe,k)+wormdisplacementx))^2 + (newleftregiony(j)-(leftregiony(previousframe,k)+wormdisplacementy))^2;
                            else
								costmatrix(j,k) = Inf;
                            end
                        end
                    end
                end
                
                %Speed thresholding before the assignment is made
                if speedthreshold ~= 0
                    for j=1:numberofnewregions
                        for k=1:numberofregions(previousframe)
                            if realsqrt(costmatrix(j, k)) > speedthreshold
                                costmatrix(j, k) = Inf;
                            end
                        end
                    end
                end
				
				assignment = assignmentoptimal(costmatrix); %Solving the across-frame assignment problem using the Hungarian algorithm
				
				%fprintf('at frame %d (previousframe=%d), the size of the assignment matrix is %d %d , and its contents are:\n',i, previousframe, size(assignment, 1), size(assignment, 2));
				%disp(assignment);
				%disp('-');

%                disp('costmatrix=');
%                disp(costmatrix);
%                disp('assignment=');
%                disp(assignment);

                previousdisplacementx = NaN(1, numberofnewregions);
                previousdisplacementy = NaN(1, numberofnewregions);

				%Pair regions that can be paired
				for j=1:numel(assignment)
					if assignment(j) ~= 0 %if it is paired with something (i.e. newregion(j) is paired with region(previousframe, assignment(j)))
						numberofregions(i) = numberofregions(i) + 1;
						leftregionx(i,numberofregions(i)) = newleftregionx(j);
						leftregiony(i,numberofregions(i)) = newleftregiony(j);
                        leftregionz(i,numberofregions(i)) = 1;
						rightregionx(i,numberofregions(i)) = newrightregionx(j);
						rightregiony(i,numberofregions(i)) = newrightregiony(j);
                        rightregionz(i,numberofregions(i)) = 1;
						leftregionradius(i,numberofregions(i)) = newleftregionradius(j);
						rightregionradius(i,numberofregions(i)) = newrightregionradius(j);
						regionimportant(i, numberofregions(i)) = true;
						regionname(i,numberofregions(i),:) = regionname(previousframe, assignment(j), :);
						hasbeenpaired(j) = 1;
                        
                        previousdisplacementx(numberofregions(i)) = newleftregionx(j) - leftregionx(previousframe, assignment(j));
                        previousdisplacementy(numberofregions(i)) = newleftregiony(j) - leftregiony(previousframe, assignment(j));
					end
				end
            else
                previousdisplacementx = NaN(1, numberofnewregions);
                previousdisplacementy = NaN(1, numberofnewregions);
            end
			
%            disp('hasbeenpaired=');
%            disp(hasbeenpaired);

			%Add regions which could not be paired previously to
			%the end of the list
			for j=1:numberofnewregions
				if (hasbeenpaired(j) == 0)
					maxnumberofregions = maxnumberofregions + 1;
					if (maxnumberofregions == 1)
						canselectregion = true;
						set(controlselectregion,'Enable','on'); %now that there is a region detected, enable ability to select regions
						canshowneurons = true;
						set(handles.showneurons,'Enable','on','Value',1);
						canadjustmeasurement = true;
						set(controladjustmeasurement,'Enable','on');
						switchforeground;
						switchbackground;
					end
					numberofregions(i) = numberofregions(i) + 1;
					leftregionx(i,numberofregions(i)) = newleftregionx(j);
					leftregiony(i,numberofregions(i)) = newleftregiony(j);
                    leftregionz(i,numberofregions(i)) = 1;
					rightregionx(i,numberofregions(i)) = newrightregionx(j);
					rightregiony(i,numberofregions(i)) = newrightregiony(j);
                    rightregionz(i,numberofregions(i)) = 1;
					leftregionradius(i,numberofregions(i)) = newleftregionradius(j);
					rightregionradius(i,numberofregions(i)) = newrightregionradius(j);
					regionimportant(i, numberofregions(i)) = true;
					newnamestring = num2str(maxnumberofregions);
					if (size(newnamestring,2) < 5) %Const size strings enforced
						newnamestring(size(newnamestring,2)+1:5) = ones(5-size(newnamestring,2),1)*32;
					elseif (size(newnamestring,2) > 5)
                        fprintf('Error: name of the new detected region at frame %d (%s) is too long.\n', i, newnamestring);
					end
					regionname(i,numberofregions(i),:) = newnamestring;
				end
			end

        end
        
        frameslookedat = (ito-ifrom+1);
        if frameslookedat > 0 %If the user cancels the neuron detection even before the first frame is processed, don't display results and don't divide by zero
            fprintf('Regions of interest were found in %d of %d frames altogether (%3.1f%%).\n',frameslookedat-numberskipped, frameslookedat, (frameslookedat-numberskipped)/frameslookedat*100.0);
            fprintf('Adjacent-frame worm displacement vectors were not possible to calculate for %d of %d frames (%3.1f%%).\n', numberfellback, frameslookedat, numberfellback/frameslookedat*100.0);
            if (usingleft && usingright) && (str2double(get(handles.withinframethresholdbox,'String')) ~= 0)
                fprintf('Region creation was suspended due to unreasonable across-channel assignment costs in %d of %d frames (%3.1f%%).\n', numberframeignored, frameslookedat, numberframeignored/frameslookedat*100.0);
            end
            if (str2double(get(handles.speedthresholdbox, 'String')) ~= 0)
                fprintf('New identities were forced due to inconsistent perceived region movements in %d of %d frames (%3.1f%%).\n', numberforcednew, frameslookedat, numberforcednew/frameslookedat*100.0);
            end
            fprintf('The highest number of regions found per frame is %d.\n', max(numberofregions(:)));
            fprintf('%d different identities were assigned to the regions altogether.\n',maxnumberofregions);
        end
        
        if ishandle(waithandle)
            close(waithandle);
        end
        
        if (maxnumberofregions > 0)
            cancalculate = true;
        end
        
        updatevisibility;
        showframe(hobj,eventdata);
        
    end

    function showframe(hobj,eventdata) %#ok<INUSD>
        
        frame = round(get(handles.frame,'Value'));
        set(handles.frame,'Value', frame); %enforces non-double precision
        
        preserveselection;
        preserveapply;
        
        if ~dontupdateframe
            if (isnan(subchannelsizex) || subchannelsizex == 0 || isnan(subchannelsizex) || subchannelsizex == 0) && get(handles.channel, 'Value') ~= 1
                fprintf('Warning: channel size is zero.');
                if (get(handles.channel, 'Value') ~= 1)
                    set(handles.channel, 'Value', 1);
                    fprintf(' Switching view to original.');
                end
                fprintf('\n');
            end
            
            updatebehaviour;
            
            delete(get(handles.img, 'Children'));
            
            showtwo = false; % showing regions in two subimages
            showoriginal = false; % In original view, we don't have to care about cropping and alignment and all that
            showrightlocation = false; % If we have only one window, show the right channel's recognized neurons' location instead of that of the left channel
            showneuronlocations = (get(handles.showneurons,'Value')==1);
            switch get(handles.channel,'Value')
                case 1 %original
                    if stacktucam
                        imshow([readframe(frame, 1) readframe(frame, 2)], [], 'Parent', handles.img);
                    else
                        imshow(readframe(frame), [], 'Parent', handles.img);
                    end
                    if get(handles.channelchooser, 'Value') ~= 3
                        showtwo = true;
                    end
                    showoriginal = true;
                case 2 %split
                    cachesubimages(frame);
                    lefttoshow = LEFT(frame);
                    if get(handles.showarb, 'Value')
                        lefttoshow(~squeeze(arbarea(frame, :, :))) = Inf;
                    end
                    righttoshow = RIGHT(frame);
                    if get(handles.showarb, 'Value')
                        righttoshow(~squeeze(arbarea(frame, :, :))) = Inf;
                    end
                    imshow([lefttoshow righttoshow], [], 'Parent', handles.img);
                    showtwo = true;
                case 3 %splitregions
                    if leftthreshold > 0 && rightthreshold > 0
                        cachesubimages(frame);
                    end
                    if leftthreshold > 0
                        leftframenow = LEFT(frame);
                        if gaussianx > 0 %If using filters
                            leftframenow = imfilter(leftframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                        end
                        leftframenow = leftframenow > leftthreshold;
                    else
                        leftframenow = ones(subchannelsizey, subchannelsizex);
                    end
                    if rightthreshold > 0
                        rightframenow = RIGHT(frame);
                        if gaussianx > 0 %If using filters
                            rightframenow = imfilter(rightframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                        end
                        rightframenow = rightframenow > rightthreshold;
                    else
                        rightframenow = ones(subchannelsizey, subchannelsizex);
                    end
                    imshow([leftframenow rightframenow], [], 'Parent', handles.img);
                    showtwo = true;
                case 4 %left
                    if get(handles.channelchooser, 'Value') ~= 3
                        lefttoshow = LEFT(frame);
                        if get(handles.showarb, 'Value')
                            lefttoshow(~squeeze(arbarea(frame, :, :))) = Inf;
                        end
                        imshow(lefttoshow, [], 'Parent', handles.img);
                    else
                        imshow(NaN(subchannelsizey, subchannelsizex), 'Parent', handles.img);
                    end
                case 5 %right
                    if get(handles.channelchooser, 'Value') ~= 3
                        righttoshow = RIGHT(frame);
                        if get(handles.showarb, 'Value')
                            righttoshow(~squeeze(arbarea(frame, :, :))) = Inf;
                        end
                        imshow(righttoshow, [], 'Parent', handles.img);
                        showrightlocation = true;
                    else
                        imshow(NaN(subchannelsizey, subchannelsizex), 'Parent', handles.img);
                    end
                case 6 %LEFTregions
                    if get(handles.channelchooser, 'Value') ~= 3
                        leftframenow = LEFT(frame);
                        if gaussianx > 0 %If using filters
                            lblurred = imfilter(leftframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                        else
                            lblurred = leftframenow;
                        end
                        llogical = im2bw(lblurred/65535,leftthreshold/65535); %mark pixels above threshold as 1
                        llabel = bwlabel(llogical);
                        imshow(llabel, [], 'Parent', handles.img);
                    else
                        imshow(NaN(subchannelsizey, subchannelsizex), 'Parent', handles.img);
                    end
                case 7 %RIGHTregions
                    if get(handles.channelchooser, 'Value') ~= 3
                        rightframenow = RIGHT(frame);
                        if gaussianx > 0 %If using filters
                            rblurred = imfilter(rightframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                        else
                            rblurred = rightframenow;
                        end
                        rlogical = im2bw(rblurred/65535,rightthreshold/65535); %mark pixels above threshold as 1
                        rlabel = bwlabel(rlogical);
                        imshow(rlabel,[],'Parent',handles.img);
                        showrightlocation = true;
                    else
                        imshow(NaN(subchannelsizey, subchannelsizex), 'Parent', handles.img);
                    end
                case 8 %Ratio
                    if get(handles.channelchooser, 'Value') ~= 3
                        cachesubimages(frame);
                        leftframenow = LEFT(frame);
                        rightframenow = RIGHT(frame);
                        if gaussianx > 0 %If using filters
                            leftframenow = imfilter(leftframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                            rightframenow = imfilter(rightframenow, gaussianfilter); %blur it a bit so that we get continuous areas
                        end
                        if (get(handles.channelchooser, 'Value') == 1)
                            imshow(((leftframenow./rightframenow)-correctionfactorA) * correctionfactorB,[],'Parent',handles.img);
                        else
                            imshow(((rightframenow./leftframenow)-correctionfactorA) * correctionfactorB,[],'Parent',handles.img);
                        end
                        showneuronlocations = false;
                    else
                        imshow(NaN(subchannelsizey, subchannelsizex), 'Parent', handles.img);
                    end
            end
            set(handles.fig,'Colormap',colormap(jet));
            set(handles.img,'NextPlot','add');
            if frame == 0
                fprintf('Warning: frame number 0 was requested in function showframe. Frame number set to 1 instead.\n');
                frame = 1;
            end
            if showneuronlocations
                if ~isempty(leftregionx)
                    currentnumberofregions = numberofregions(frame);
                elseif ~isempty(detectedframes)
                    currentnumberofregions = numel(detectedframes(frame).vertices);
                else
                    currentnumberofregions = 0;
                end
                for j=1:currentnumberofregions % j = region ID
                    
                    if ~isempty(leftregionx)
                        leftpeakx = leftregionx(frame,j);
                        leftpeaky = leftregiony(frame,j);
                        leftradius = leftregionradius(frame,j);
                        rightpeakx = rightregionx(frame,j);
                        rightpeaky = rightregiony(frame,j);
                        rightradius = rightregionradius(frame,j);
                        if exist('leftregionz', 'var') == 1 && number(leftregionz) > 0
                            leftpeakz = leftregionz(frame,j);
                        end
                        if exist('rightregionz', 'var') == 1 && number(rightregionz) > 0
                            rightpeakz = rightregionz(frame,j);
                        end
                    elseif ~isempty(detectedframes)
                        leftpeakx = detectedframes(frame).vertices(j).x;
                        rightpeakx = detectedframes(frame).vertices(j).x;
                        leftpeaky = detectedframes(frame).vertices(j).y;
                        rightpeaky = detectedframes(frame).vertices(j).y;
                        if numel(uniqueposz) > 0
                            leftpeakz = detectedframes(frame).vertices(j).z;
                            rightpeakz = detectedframes(frame).vertices(j).z;
                        end
                        leftradius = realsqrt(detectedframes(frame).vertices(j).area);
                        rightradius = leftradius;
                    end
                    
                    if number(uniqueposz) > 0 && ~get(handles.maxproject, 'Value')
                        znow = uniqueposz(get(handles.zpos, 'Value'));
                        leftpeakz = uniqueposz(round(leftpeakz));
                        rightpeakz = uniqueposz(round(rightpeakz));
                        leftzdiff = abs(leftpeakz-znow);
                        rightzdiff = abs(rightpeakz-znow);
                        if number(xmlstruct) > 0 && isfield(xmlstruct, 'xyintoz')
                            xyconversionfactor = xmlstruct.xyintoz;
                        end
                        leftradius = leftradius * xyconversionfactor; %converting them to the same units as the z-distances
                        rightradius = rightradius * xyconversionfactor;
                        if leftzdiff <= leftradius
                            leftradius = realsqrt(leftradius^2-leftzdiff^2);
                        else
                            leftradius = 0;
                        end
                        if rightzdiff <= rightradius
                            rightradius = realsqrt(rightradius^2-rightzdiff^2);
                        else
                            rightradius = 0;
                        end
                        leftradius = leftradius / xyconversionfactor; %converting them back to pixels
                        rightradius = rightradius / xyconversionfactor;
                    end

                    if get(handles.channelchooser, 'Value') == 1
                        leftcolour = 'y';
                        rightcolour = 'c';
                    elseif get(handles.channelchooser, 'Value') == 2
                        leftcolour = 'c';
                        rightcolour = 'y';
                    elseif get(handles.channelchooser, 'Value') == 3
                        leftcolour = 'r';
                        rightcolour = 'r';
                    end
                    if j == selectedregion
                        circlecolour = [1 0.2 1]; %bright magenta
                    else
                        circlecolour = [0.7 0 0]; %dark red
                    end
                    

                    if isempty(leftpeakx) || isempty(leftpeaky) || isempty(rightpeakx) || isempty(rightpeaky) || leftpeakx==0 || leftpeaky==0 || rightpeakx==0 || rightpeaky==0
                        continue
                    end
                    
                    if ~isempty(leftregionx)
                        currentname = strtrim(char(squeeze(regionname(frame,j,:))'));
                    elseif ~isempty(detectedframes)
                        currentname = '';
                        if number(detectedneurons) > 0
                            for i=1:numel(detectedneurons)
                                if detectedneurons(i).whichinframe(frame) == j
                                    currentname = strtrim(char(squeeze(sprintf('%d', i))));
                                    break;
                                end
                            end
                        else
                            currentname = strtrim(char(squeeze(sprintf('%d', j))));
                        end
                    end

                    if showtwo
                        if showoriginal
                            leftpeaky = leftpeaky + max(-rightdisplacementy,1)+croptop - 1;
                            rightpeaky = rightpeaky + max(rightdisplacementy,1)+croptop - 1;
                            leftpeakx = leftpeakx + max(unusablerightx,1)+cropleft - 1;
                            rightpeakx = rightpeakx + rightdisplacementx+unusablerightx+cropleft - 1;
                        else %if split view
                            rightpeakx = rightpeakx + subchannelsizex;
                        end
                    elseif showoriginal && get(handles.channelchooser, 'Value') == 3
                        leftpeakx = leftpeakx + cropleft;
                        leftpeaky = leftpeaky + croptop;
                    end

                    if ~showrightlocation %If showing Left
                        plot(handles.img,leftpeakx,leftpeaky,'xk', 'Markersize', 3);
                        plot(handles.img,ceil(leftradius*radius)*circlepointsx+leftpeakx, ceil(leftradius*radius)*circlepointsy+leftpeaky, '-', 'MarkerSize', 1, 'Color', circlecolour);
                        if get(handles.backgroundpopup, 'Value') == 1 && get(handles.localbackground, 'Value')
                            plot(handles.img,ceil(leftradius*radius*2.5)*circlepointsx+leftpeakx, ceil(leftradius*radius*2.5)*circlepointsy+leftpeaky, '-', 'MarkerSize', 1, 'Color', 'k');
                        end
                        text(leftpeakx+4,leftpeaky-4,currentname,'Color',leftcolour,'Margin',0.001,...
                        'BackgroundColor','k','Parent',handles.img,...
                        'FontSize',7,'Interpreter','none');
                    end
                    if showrightlocation || showtwo %If showing Right
                        plot(handles.img,rightpeakx,rightpeaky,'xk', 'Markersize', 3);
                        plot(handles.img,ceil(rightradius*radius)*circlepointsx+rightpeakx, ceil(rightradius*radius)*circlepointsy+rightpeaky, '-', 'MarkerSize', 1, 'Color', circlecolour);
                        if get(handles.backgroundpopup, 'Value') == 1 && get(handles.localbackground, 'Value')
                            plot(handles.img,ceil(rightradius*radius*2.5)*circlepointsx+rightpeakx, ceil(rightradius*radius*2.5)*circlepointsy+rightpeaky, '-', 'MarkerSize', 1, 'Color', 'k');
                        end
                        text(rightpeakx+4,rightpeaky-4,currentname,'Color',rightcolour,'Margin',0.001,...
                        'BackgroundColor','k','Parent',handles.img,...
                        'FontSize',7,'Interpreter','none');
                    end
                end
            end
            %{
            if get(handles.showarb, 'Value')
                if showtwo
                    if showoriginal
                        arbareatodisplay = [false(subchannelsizey, cropleft)  arbarea];
                        if rightdisplacementx-subchannelsizex > 0
                            arbareatodisplay = [arbareatodisplay false(subchannelsizey, rightdisplacementx-subchannelsizex)];
                        end
                        arbareatodisplay = [arbareatodisplay arbarea];
                        arbareatodisplay = [false(croptop, size(arbareatodisplay, 2));arbareatodisplay];
                    else %if split view
                        arbareatodisplay = [arbarea arbarea];
                    end
                else
                    arbareatodisplay = arbarea;
                end
                %{
                elseif showoriginal && get(handles.channelchooser, 'Value') == 3
                    leftpeakx = leftpeakx + cropleft;
                    leftpeaky = leftpeaky + croptop;
                end
                %}
            end
            %}
            set(handles.img,'NextPlot','replace');
            set(handles.caption,'String',newfile);
            set(handles.setframe, 'String', num2str(frame));
            set(handles.nftext, 'String', ['/ ' num2str(nf)]);
        end
        
    end

    function minusfifty(hobj, eventdata) %#ok<INUSD>
        frame = frame - 50;
        if (frame < 1)
            frame = 1;
        end
        set(handles.frame,'Value', frame);
        showframe;
    end

    function plusfifty(hobj, eventdata) %#ok<INUSD>
        frame = frame + 50;
        if (frame > nf)
            frame = nf;
        end
        set(handles.frame,'Value', frame);
        showframe;
    end

    function makefigure (hobj, eventdata) %#ok<INUSD>
        cla(handles.img);
        figure;
        handles.img = gca;
        showframe;
        title(sprintf('%s : frame %d/%d',newfile,frame,nf), 'Interpreter', 'none');
        colormap(jet);
        colorbar;
        xlabel('x-position (pixel)');
        ylabel('y-position (pixel)');
        handles.img = axes('Parent',handles.previewpanel,'Visible','on', 'Position',[0.00 0.13 1.00 0.87]);
        showframe;
    end

    function setradius(hobj,eventdata,step)
        if nargin<3
            radstr = str2double(get(handles.radiusmultiplier,'String'));
            if ~isnan(radstr)
                radius = radstr;
            end
        else
            if (radius == 0.01 && step == 1)
                radius = 1.00;
            else
                radius = radius + step;
            end
        end
		radius = bound(radius, 0.0, 1000.0); %So that it's possible to set a radius multiplier smaller than 1, e.g. 0.1...
		if radius == 0.0 %...but not a multiplier of 0
			radius = 0.01;
		end
		set(handles.radiusmultiplier,'String',num2str(radius))
        showframe(hobj, eventdata);
    end

    function setpixelnumber(hobj,eventdata) %#ok<INUSD>
        pixeltosumnumber = str2double(get(handles.pixelnumber,'String'));
        if (get(handles.foregroundpopup, 'Value') == 1) % If using fixed number of pixels
            pixeltosumnumber = round(pixeltosumnumber); %we must have a non-fractional number of pixels
        end
        if ~isnan(pixeltosumnumber)
            pixelnumber = pixeltosumnumber;
        end
        if (get(handles.foregroundpopup, 'Value') == 1) %Fixed number of pixels limits
			pixelnumber = bound(pixelnumber, 1, max(originalsizex*originalsizey,1));
        elseif (get(handles.foregroundpopup, 'Value') == 2) %Fixed proportion of pixels limits
			pixelnumber = bound(pixelnumber, 0.0, 1.0); %So that it's possible to specify a proportion smaller than 1, e.g. 0.1...
            if pixelnumber == 0.0 %...but not a proportion of 0
                pixelnumber = 0.001;
            end
        end
        set(handles.pixelnumber,'String',num2str(pixelnumber));
    end

    function setpercentile(hobj,eventdata)
        percentilenumber = round(str2double(get(handles.percentile,'String')));
        if ~isnan(percentilenumber)
            percentile = percentilenumber;
        end
		percentile = bound(percentile, 0, 100); %So that it's possible to specify percentiles smaller than 1, e.g. 0.1%...
        if percentile == 0 %...but not 0 percentile 
            percentile = 1;
        end
        set(handles.percentile,'String',num2str(percentile));
        showframe(hobj, eventdata);
    end

    function setmedianoffset (hobj, eventdata)
        cachesubimages(frame);
        leftvalues = LEFT(frame);
        rightvalues = RIGHT(frame);
        valuestogether = [leftvalues(:);rightvalues(:)];
        offset = bound(median(valuestogether), 0, 2^24-1);
        set(handles.offset,'String',num2str(offset));
        set(handles.backgroundpopup, 'Value', 3);
        switchbackground;
        showframe(hobj, eventdata);
    end

    function setcropbottom (hobj, eventdata) %#ok<INUSD>
        %clearallregions;
        tempnewvalue = round(str2double(get(handles.cropbottom, 'String')));
        if ~isnan(tempnewvalue)
            cropbottom = tempnewvalue;
        end
		cropbottom = bound(cropbottom, 0, originalsizey);
        set(handles.cropbottom,'String',num2str(cropbottom));
        updatesubchannelsizes;
        showframe;
    end

    function setcroptop (hobj, eventdata) %#ok<INUSD>
        %clearallregions;
        tempnewvalue = round(str2double(get(handles.croptop, 'String')));
        if ~isnan(tempnewvalue)
            croptop = tempnewvalue;
        end
		croptop = bound(croptop, 0, originalsizey);
        set(handles.croptop,'String',num2str(croptop));
        updatesubchannelsizes;
        showframe;
    end

    function setcropright (hobj, eventdata) %#ok<INUSD>
        %clearallregions;
        tempnewvalue = round(str2double(get(handles.cropright, 'String')));
        if ~isnan(tempnewvalue)
            cropright = tempnewvalue;
        end
		cropright = bound(cropright, 0, originalsizex);
        set(handles.cropright,'String',num2str(cropright));
        updatesubchannelsizes;
        showframe;
    end

    function setcropleft (hobj, eventdata) %#ok<INUSD>
        %clearallregions;
        tempnewvalue = round(str2double(get(handles.cropleft, 'String')));
        if ~isnan(tempnewvalue)
            cropleft = tempnewvalue;
        end
		cropleft = bound(cropleft, 0, originalsizex);
        set(handles.cropleft,'String',num2str(cropleft));
        updatesubchannelsizes;
        showframe;
    end

    function setcroplmiddle (hobj, eventdata) %#ok<INUSD>
        %clearallregions;
        tempnewvalue = round(str2double(get(handles.croplmiddle, 'String')));
        if ~isnan(tempnewvalue)
            leftwidth = tempnewvalue;
        end
        leftwidth = bound(leftwidth, 1, max([rightdisplacementx+unusablerightx-1 1]));
        set(handles.croplmiddle,'String',num2str(leftwidth));
        updatesubchannelsizes;
        showframe;
    end

    function setcroprmiddle (hobj, eventdata) %#ok<INUSD>
        %clearallregions;
        tempnewvalue = round(str2double(get(handles.croprmiddle, 'String')));
        if ~isnan(tempnewvalue)
            unusablerightx = tempnewvalue - rightdisplacementx;
        end
        unusablerightx = bound(unusablerightx, 0, originalsizex);
        set(handles.croprmiddle,'String',num2str(rightdisplacementx + unusablerightx));
        updatesubchannelsizes;
        showframe;
    end

    function setalignmentsearchradius(hobj,eventdata) %#ok<INUSD>
        alignmentsearchnumber = round(str2double(get(handles.alignmentsearchradius,'String')));
        if ~isnan(alignmentsearchnumber)
            alignmentsearchradius = alignmentsearchnumber;
        end
		alignmentsearchradius = bound(alignmentsearchradius, 0, max(originalsizex, originalsizey));
		set(handles.alignmentsearchradius,'String',num2str(alignmentsearchradius));
        showframe;
    end

    function setcorrectionsearchradius(hobj,eventdata)
        correctionsearchnumber = round(str2double(get(handles.correctionsearchradius,'String')));
        if ~isnan(correctionsearchnumber)
            correctionsearchradius = correctionsearchnumber;
        end
		correctionsearchradius = bound(correctionsearchradius, 0, max(originalsizex, originalsizey));
		set(handles.correctionsearchradius,'String',num2str(correctionsearchradius));
        showframe(hobj, eventdata);
    end

    function setminimalneuronsize(hobj,eventdata)
        neuronsizenumber = round(str2double(get(handles.minimalneuronsize,'String')));
        if ~isnan(neuronsizenumber)
            minimalneuronsize = neuronsizenumber;
        end
		minimalneuronsize = bound(minimalneuronsize, 1, max(originalsizex*originalsizey,1));
		set(handles.minimalneuronsize,'String',num2str(minimalneuronsize));
        showframe(hobj, eventdata);
    end

    function setz(hobj, eventdata, setfromwhich) %#ok<INUSL>
        if exist('setfromwhich', 'var') ~= 1
            setfromwhich = 'setz';
        end
        setznumber = str2double(get(handles.setz, 'String'));
        zposnumber = get(handles.zpos, 'Value');
        if strcmpi(setfromwhich, 'setz') && ~isnan(setznumber)
            z = setznumber;
        elseif strcmpi(setfromwhich, 'zpos') && ~isnan(zposnumber)
            z = uniqueposz(round(zposnumber));
        else
            z = median(uniqueposz);
        end
        distancefromvalids = abs(uniqueposz - z);
        [mindistance, minwho] = min(distancefromvalids);
        set(handles.setz, 'String', num2str(uniqueposz(minwho)));
        set(handles.zpos, 'Value', minwho);
        showframe;
    end

    function setframe(hobj, eventdata)
        framenumber = round(str2double(get(handles.setframe,'String')));
        frame = round(get(handles.frame,'Value'));
        if ~isnan(framenumber)
            frame = framenumber;
        end
		frame = bound(frame, 1, nf);
        set(handles.setframe,'String',num2str(frame));
        set(handles.frame,'Value', frame); %Moves slider
        showframe(hobj, eventdata);
    end

    function calculateratios (hobj, eventdata) %#ok<INUSD>
        currentlycalculating = true;
        maxnumberofexistingregions = max(max(numberofregions(:)),1);
        ratios = NaN(nf,maxnumberofexistingregions);
        leftvalues = NaN(nf, maxnumberofexistingregions);
        rightvalues = NaN(nf, maxnumberofexistingregions);
        leftbackground = NaN(nf, maxnumberofexistingregions);
        rightbackground = NaN(nf, maxnumberofexistingregions);
        rationames = ones(maxnumberofexistingregions, 5)*32;
        numberofregionsfound = 0;

        set(controlcrop, 'Enable', 'off');
        set(controlmanipulate, 'Enable', 'off');
        set(controlsetalignment, 'Enable', 'off');
        set(controldetect, 'Enable', 'off');
        set(controladjustregion,'Enable','off');
        set(controladjustmeasurement, 'Enable', 'off');
        set(handles.load, 'Enable', 'off');
        set(controlcalculate, 'Enable', 'off');
        set(handles.channelchooser, 'Enable', 'off');
        set(handles.correctionfactorA, 'Enable', 'off');
        set(handles.correctionfactorAtext, 'Enable', 'off');
        set(handles.correctionfactorB, 'Enable', 'off');
        set(handles.correctionfactorBtext, 'Enable', 'off');
        set(handles.readspeed, 'Enable', 'off');
        
        waithandle = waitbar(0,'Ratio calculation...','Name','Processing', 'CreateCancelBtn', 'delete(gcbf)');
        
        cachedbackground = 0; %with some settings (currently all settings), the background is the same for all regions within a frame, so it's not necessary to calculate them again for more than one region per frame. So it makes sense to cache it. This is the index of the frame whose background is cached.
        
        if fileformat == CONST_FILEFORMAT_BIOFORMATS && get(handles.localbackground, 'Value') == 1 && get(handles.backgroundpopup, 'Value') == 1 && false %changeme: currently disabled
            onlyreadlocally = true;
        else
            onlyreadlocally = false;
        end
        
        withinrange(0, 0, 0, 0, 0, 0); %clearing persistent variables from withinrange to ensure no contamination from potentially old versions of the file
        
        for i=1:nf % i = actual frame
            if numberofregions(i) > 0 || any(arbarea(:))
                %check if there is something to measure at all before caching frames, etc
                thereissomething = false;
                for j=1:numberofregions(i)
                    if regionimportant(i, j) && (leftregionx(i,j)~=0) && (leftregiony(i,j)~=0) && (rightregionx(i,j)~=0) && (rightregiony(i,j)~=0)
                        thereissomething = true;
                        break;
                    end
                end
                if any(arbarea(:))
                    thereissomething = true;
                end
                
                if thereissomething
                
                    if get(handles.channelchooser, 'Value') ~= 3 && ~onlyreadlocally
                        cachesubimages(i);
                        leftframenow = LEFT(i);
                        rightframenow = RIGHT(i);
                    end
                    
                    for j=1:numberofregions(i)+any(arbarea(:)) % j = region ID

                        if j <= numberofregions(i)
                            leftpeakx = leftregionx(i,j);
                            leftpeaky = leftregiony(i,j);
                            rightpeakx = rightregionx(i,j);
                            rightpeaky = rightregiony(i,j);

                            if (leftpeakx==0) || (leftpeaky==0) || (rightpeakx == 0) || (rightpeaky == 0) || (~regionimportant(i,j))
                                continue;
                            end

                            actualradiusl = leftregionradius(i,j)*radius;
                            actualradiusr = rightregionradius(i,j)*radius;

                            if ((rightpeakx + actualradiusr) > subchannelsizex) || (rightpeakx - actualradiusr < 1) || (rightpeaky + actualradiusr > subchannelsizey) || (rightpeaky - actualradiusr < 1)
                                continue; %if dangerously close to any of the edges where circmask could get out of bounds (and provide lower values for the average), don't attempt to get ratio
                            end
                            if ((leftpeakx + actualradiusl) > subchannelsizex) || (leftpeakx - actualradiusl < 1) || (leftpeaky + actualradiusl > subchannelsizey) || (leftpeaky - actualradiusl < 1)
                                continue; %if dangerously close to any of the edges where circmask could get out of bounds (and provide lower values for the average), don't attempt to get ratio
                            end
                            
                            actualbackgroundradiusl = actualradiusl * 2.5;
                            actualbackgroundradiusr = actualradiusr * 2.5;
                            
                            if onlyreadlocally
                                [xstarttoread, ystarttoread, xsizetoread, ysizetoread, lxwherenow, lywherenow] = croppedcoordinates(leftpeakx, leftpeaky, actualbackgroundradiusl);
                                leftframenow = readframe(i, 1, [], xstarttoread, ystarttoread, xsizetoread, ysizetoread);
                            else
                                lxwherenow = leftpeakx;
                                lywherenow = leftpeaky;
                            end

                            %lforegroundwhere = hypot(lmeshx-leftpeakx, lmeshy-leftpeaky) < actualradiusl; %matrix of 1s around peak with radius actualradiusl, which should be considered
                            lforegroundwhere = withinrange(size(leftframenow, 1), size(leftframenow, 2), lxwherenow, lywherenow, actualradiusl);

                            if get(handles.excludeoverlap, 'Value') == 1
                                jumptonextframe = false;
                                for k=1:numberofregions(i)
                                    if (k == j || leftregionx(i,k) == 0 || leftregiony(i,k) == 0)
                                        continue;
                                    end
                                    if hypot(leftregionx(i, k) - leftpeakx, leftregiony(i, k) - leftpeaky) < leftregionradius(i, k)*radius + actualradiusl
                                        jumptonextframe = true;
                                        break;
                                    end
                                end
                                if jumptonextframe
                                    fprintf('Warning: regions ''%s'' and ''%s'' overlap in at least the left channel in frame %d. Skipping this region in this frame.\n', strtrim(char(squeeze(regionname(i,j,:))')), strtrim(char(squeeze(regionname(i,k,:))')), i);
                                    continue;
                                end
                            end
                            leftpixels = leftframenow(lforegroundwhere); %getting only the pixels close to the detected peak.
                        else
                            leftpixels = leftframenow(squeeze(arbarea(i, :, :)));
                        end
                        
                        lpixelsnumber = numel(leftpixels); %use all pixels within the radius (may be adjusted later by pixelnumber)

                        if (get(handles.foregroundpopup, 'Value') == 1) %Using a fixed max number of pixels
                            lpixelsnumber = min(pixelnumber, lpixelsnumber);
                            leftpixels = sort(leftpixels(:), 'descend');
                            if (lpixelsnumber == 0)
                                fprintf('Warning: insufficient number of pixels to sum in frame %d. Increasing the radius might help.\n', i);
                                continue;
                            end
                            leftfp = mean(leftpixels(1:lpixelsnumber)); %calculate left signal based on the top lpixelnumber of pixels within the radius
                        elseif (get(handles.foregroundpopup, 'Value') == 2) %Using a fixed proportion of pixels
                            lpixelsnumber = max(round(lpixelsnumber*pixelnumber), 1);
                            leftpixels = sort(leftpixels(:),'descend');
                            leftfp = mean(leftpixels(1:lpixelsnumber)); %calculate left signal based on the top lpixelnumber of pixels within the radius
                        else %Using all pixels within the region
                            leftfp = mean(leftpixels(:));
                        end

                        if j <= numberofregions(i)
                            
                            if onlyreadlocally
                                [xstarttoread, ystarttoread, xsizetoread, ysizetoread, rxwherenow, rywherenow] = croppedcoordinates(rightpeakx, rightpeaky, actualbackgroundradiusr);
                                rightframenow = readframe(i, 2, [], xstarttoread, ystarttoread, xsizetoread, ysizetoread);
                            else
                                rxwherenow = rightpeakx;
                                rywherenow = rightpeaky;
                            end
                            
                            %rforegroundwhere = hypot(rmeshx-rightpeakx, rmeshy-rightpeaky) < actualradiusr; %matrix of 1s around peak with radius actualradiusr, which should be considered
                            rforegroundwhere = withinrange(size(rightframenow, 1), size(rightframenow, 2), rxwherenow, rywherenow, actualradiusr);

                            if get(handles.excludeoverlap, 'Value') == 1
                                jumptonextframe = false;
                                for k=1:numberofregions(i)
                                    if (k == j || rightregionx(i,k) == 0 || rightregiony(i,k) == 0)
                                        continue;
                                    end
                                    if hypot(rightregionx(i, k) - rightpeakx, rightregiony(i, k) - rightpeaky) < rightregionradius(i, k)*radius + actualradiusr
                                        jumptonextframe = true;
                                        break;
                                    end
                                end
                                if jumptonextframe
                                    fprintf('Warning: regions ''%s'' and ''%s'' overlap in the right channel in frame %d. Skipping this region in this frame.\n', strtrim(char(squeeze(regionname(i,j,:))')), strtrim(char(squeeze(regionname(i,k,:))')), i);
                                    continue;
                                end
                            end
                            rightpixels = rightframenow(rforegroundwhere); %getting only the pixels close to the detected peak.
                        else
                            rightpixels = rightframenow(squeeze(arbarea(i, :, :)));
                        end
                        
                        rpixelsnumber = numel(rightpixels); %use all pixels within the radius (may be adjusted later by pixelnumber)

                        if (get(handles.foregroundpopup, 'Value') == 1) %Using a fixed max number of pixels
                            rpixelsnumber = min(pixelnumber, rpixelsnumber);
                            rightpixels = sort(rightpixels(:), 'descend');
                            if (rpixelsnumber == 0)
                                fprintf('Warning: insufficient number of pixels to sum in frame %d. Increasing the radius might help.\n', i);
                                continue;
                            end
                            rightfp = mean(rightpixels(1:rpixelsnumber)); %calculate the signal based on the top rpixelnumber of pixels within the radius
                        elseif (get(handles.foregroundpopup, 'Value') == 2) %Using a fixed proportion of pixels
                            rpixelsnumber = max(round(rpixelsnumber*pixelnumber), 1);
                            rightpixels = sort(rightpixels(:),'descend');
                            rightfp = mean(rightpixels(1:rpixelsnumber)); %calculate the signal based on the top lpixelnumber of pixels within the radius
                        else %Using all pixels within the region
                            rightfp = mean(rightpixels(:));
                        end

                        if get(handles.localbackground, 'Value') == 1 && get(handles.backgroundpopup, 'Value') == 1
                            %lbackgroundwhere = hypot(lmeshx-leftpeakx, lmeshy-leftpeaky) < actualradiusl*2.5; %matrix of 1s around peak with radius 2*actualradiusr, which should be considered for the background
                            %rbackgroundwhere = hypot(rmeshx-rightpeakx, rmeshy-rightpeaky)  < actualradiusr*2.5; %matrix of 1s around peak with radius 2*actualradiusr, which should be considered for the background
                            lbackgroundwhere = withinrange(size(leftframenow, 1), size(leftframenow, 2), lxwherenow, lywherenow, actualbackgroundradiusl);
                            rbackgroundwhere = withinrange(size(rightframenow, 1), size(rightframenow, 2), rxwherenow, rywherenow, actualbackgroundradiusr);
                            leftbackgroundpixels = leftframenow(lbackgroundwhere);
                            rightbackgroundpixels = rightframenow(rbackgroundwhere);
                            lbgpixels = sort(leftbackgroundpixels(:),'ascend');
                            rbgpixels = sort(rightbackgroundpixels(:),'ascend');
                            numberofpixels = round(min(numel(lbgpixels), numel(rbgpixels)) * percentile / 100.0);
                            if (numberofpixels < 1) || numberofpixels > numel(lbgpixels) || numberofpixels > numel(rbgpixels)
                                fprintf('Inappropriate number of background pixels to use in frame %d . Using the median value instead.\n', i);
                                lbg = median(leftbackgroundpixels(:));
                                rbg = median(rightbackgroundpixels(:));
                            else
                                lbg = lbgpixels(numberofpixels);
                                rbg = rbgpixels(numberofpixels);
                                %fprintf('n = %d , lbg = %.1f , rbg = %.1f .\n', numberofpixels, lbg, rbg);
                            end
                        else
                            if cachedbackground ~= i %only calculate if we don't have a cached value for the background, otherwise use lbg and rbg from the previous region in the same frame
                                if get(handles.backgroundpopup, 'Value') == 1 %percentile
                                    lbgpixels = sort(leftframenow(:),'ascend');
                                    rbgpixels = sort(rightframenow(:),'ascend');
                                    numberofpixels = round(size(lbgpixels,1) * percentile / 100.0);
                                    if (numberofpixels < 1) || numberofpixels > numel(lbgpixels) || numberofpixels > numel(rbgpixels)
                                        fprintf('Inappropriate number of background pixels to use in frame %d . Using the median value instead.\n', i);
                                        lbg = median(leftframenow(:));
                                        rbg = median(rightframenow(:));
                                    else
                                        lbg = lbgpixels(numberofpixels);
                                        rbg = rbgpixels(numberofpixels);
                                        %fprintf('n = %d , lbg = %.1f , rbg = %.1f .\n', numberofpixels, lbg, rbg);
                                    end
                                elseif get(handles.backgroundpopup, 'Value') == 2 %median background
                                    lbg = median(leftframenow(:));
                                    rbg = median(rightframenow(:));
                                    %fprintf('lbg = %.1f , rbg = %.1f .\n', lbg, rbg);
                                elseif get(handles.backgroundpopup, 'Value') == 3 %camera offset
                                    lbg = offset;
                                    rbg = offset;
                                elseif get(handles.backgroundpopup, 'Value') == 4 %if using no background subtraction
                                    lbg = 0.0;
                                    rbg = 0.0;
                                else
                                    fprintf('Warning: inappropriate background subtraction method. Using no background subtraction instead. The index of the chosen method is %d .\n', get(handles.backgroundpopup, 'Value'));
                                    lbg = 0.0;
                                    rbg = 0.0;
                                end
                                cachedbackground = i;
                            end
                        end

                        previousregion = 0;
                        if j<=numberofregions(i)
                            for k = 1:numberofregionsfound
                                if strcmp(char(regionname(i,j,:)), char(rationames(k,:))) == 1
                                    previousregion = k;
                                    break;
                                end
                            end
                            if previousregion == 0
                                numberofregionsfound = numberofregionsfound + 1;
                                previousregion = numberofregionsfound;
                                rationames(numberofregionsfound,:) = regionname(i,j,:);
                            end
                        else
                            for k=1:numberofregionsfound
                                if strcmp('arb  ', char(rationames(k,:))) == 1
                                    previousregion = k;
                                    break;
                                end
                            end
                            if previousregion == 0
                                numberofregionsfound = numberofregionsfound + 1;
                                previousregion = numberofregionsfound;
                                rationames(numberofregionsfound, :) = cast('arb  ', 'double');
                            end
                        end
                        
                        if (~canplot)
                            canplot = true;
                            set(controlplot, 'Enable','on');
                        end
                        
                        leftbackground(i, previousregion) = lbg;
                        rightbackground(i, previousregion) = rbg;
                        
                        
                        leftvalues(i, previousregion) = (leftfp-lbg);
                        rightvalues(i, previousregion) = (rightfp-rbg);
                        
                        if get(handles.channelchooser, 'Value') == 1
                            %leftvalues(i, previousregion) = leftvalues(i, previousregion) - rightvalues(i, previousregion) * correctionfactor;
                            ratios(i, previousregion) = ((leftvalues(i, previousregion)/rightvalues(i, previousregion)) - correctionfactorA) * correctionfactorB;
                        elseif get(handles.channelchooser, 'Value') == 2
                            %rightvalues(i, previousregion) = rightvalues(i, previousregion) - leftvalues(i, previousregion) * correctionfactor;
                            ratios(i, previousregion) = ((rightvalues(i, previousregion)/leftvalues(i, previousregion)) - correctionfactorA) * correctionfactorB;
                        end
                        
                    end
                    
                    %by having it within the "if thereissomething" block,
                    %it will not be updated when there's nothing to measure
                    %in a frame, so it will jump faster to where
                    %measurement starts
                    if ishandle(waithandle)
                        if mod(i, waitbarfps) == 0 || (exist('nf1', 'var') == 1 && nf1/nf >= waitbarfps)
                            waitbar(i/nf,waithandle);
                        end
                    else
                        break;
                    end

                end
            end

        end

        if ishandle(waithandle)
            close(waithandle);
        end
        if currentlyselected
            canadjustregion = true;
        end
        if canplot
            canmanipulate = true; %enabling manipulation controls only if there is measured data to work with, and only after calculation is finished
        end
        updatevisibility;
        currentlycalculating = false;
    end

    function [xstarttoread, ystarttoread, xsizetoread, ysizetoread, xmiddlewhere, ymiddlewhere] = croppedcoordinates(peakx, peaky, radiustouse)
        xsizetoread = ceil(1+radiustouse*2);
        ysizetoread = ceil(1+radiustouse*2);
        xstarttoread = peakx-radiustouse;
        ystarttoread = peaky-radiustouse;
        xmiddlewhere = radiustouse+1;
        ymiddlewhere = radiustouse+1;
        adjustxby = xstarttoread - floor(xstarttoread);
        xstarttoread = floor(xstarttoread);
        xmiddlewhere = xmiddlewhere + adjustxby;
        adjustyby = ystarttoread - floor(ystarttoread);
        ystarttoread = floor(ystarttoread);
        ymiddlewhere = ymiddlewhere + adjustyby;
        if xstarttoread < 1
            adjustxby = 1 - xstarttoread;
            xstarttoread = 1;
            xsizetoread = xsizetoread - adjustxby;
            xmiddlewhere = xmiddlewhere - adjustxby;
        end
        if ystarttoread < 1
            adjustyby = 1 - ystarttoread;
            ystarttoread = 1;
            ysizetoread = ysizetoread - adjustyby;
            ymiddlewhere = ymiddlewhere - adjustyby;
        end
        if xstarttoread + xsizetoread > subchannelsizex
            xsizetoread = subchannelsizex - xstarttoread;
        end
        if ystarttoread + ysizetoread > subchannelsizex
            ysizetoread = subchannelsizey - ystarttoread;
        end
    end

    function savesettings(hobj,eventdata) %#ok<INUSD>
        settingsdata = struct;
        settingsdata.figureposition = get(handles.fig, 'OuterPosition');
        settingsdata.currentpath = get(handles.folder, 'String');
        settingsdata.channelchooser = get(handles.channelchooser, 'Value');
        settingsdata.cropleft = cropleft;
        settingsdata.cropright = cropright;
        settingsdata.croptop = croptop;
        settingsdata.cropbottom = cropbottom;
        settingsdata.leftwidth = leftwidth;
        settingsdata.unusablerightx = unusablerightx;
        settingsdata.rightdisplacementx = rightdisplacementx;
        settingsdata.rightdisplacementy = rightdisplacementy;
        settingsdata.correctionfactorA = correctionfactorA;
        settingsdata.correctionfactorB = correctionfactorB;
        save([mfilename '-options.mat'], '-struct', 'settingsdata');
    end

    function loadsettings
        if (exist([mfilename '-options.mat'], 'file') ~= 0) %If position savefile exists
            settingsdata = load([mfilename '-options.mat']);
            if isfield(settingsdata, 'currentpath')
                currentpath = settingsdata.currentpath;
            elseif isfield(settingsdata, 'path')
                currentpath = settingsdata.path;
            else
                currentpath = [];
            end
            set(handles.folder,'String', currentpath);
            if isfield(settingsdata, 'figureposition')
                set(handles.fig, 'OuterPosition', settingsdata.figureposition);
            end
            if isfield(settingsdata, 'channelchooser')
                set(handles.channelchooser, 'Value', settingsdata.channelchooser);
            end
            if isfield(settingsdata, 'cropleft')
                cropleft = settingsdata.cropleft;
                set(handles.cropleft,'String',num2str(cropleft));
            end
            if isfield(settingsdata, 'cropright')
                cropright = settingsdata.cropright;
                set(handles.cropright,'String',num2str(cropright));
            end
            if isfield(settingsdata, 'croptop')
                croptop = settingsdata.croptop;
                set(handles.croptop,'String',num2str(croptop));
            end
            if isfield(settingsdata, 'cropbottom')
                cropbottom = settingsdata.cropbottom;
                set(handles.cropbottom,'String',num2str(cropbottom));
            end
            if isfield(settingsdata, 'leftwidth')
                leftwidth = settingsdata.leftwidth;
                set(handles.croplmiddle, 'String', num2str(leftwidth));
            end
            if isfield(settingsdata, 'rightdisplacementx')
                rightdisplacementx = settingsdata.rightdisplacementx;
                set(handles.alignmentx, 'String', num2str(rightdisplacementx));
            end
            if isfield(settingsdata, 'rightdisplacementy')
                rightdisplacementy = settingsdata.rightdisplacementy;
                set(handles.alignmenty, 'String', num2str(rightdisplacementy));
            end
            if isfield(settingsdata, 'unusablerightx')
                unusablerightx = settingsdata.unusablerightx;
                set(handles.croprmiddle, 'String', num2str(rightdisplacementx+unusablerightx))
            end
            if isfield(settingsdata, 'correctionfactorA')
                correctionfactorA = settingsdata.correctionfactorA;
                set(handles.correctionfactorA, 'String', num2str(correctionfactorA));
            end
            if isfield(settingsdata, 'correctionfactorB')
                correctionfactorB = settingsdata.correctionfactorB;
                set(handles.correctionfactorB, 'String', num2str(correctionfactorB));
            end
            updatesubchannelsizes;
        else
            set(handles.fig, 'OuterPosition', get(0, 'Screensize'));
        end
        % disp(get(handles.fig, 'OuterPosition'));
    end

    function plotratios(hobj,eventdata) %#ok<INUSD>
        ratios(ratios == 0) = NaN;
        
        movingaverage = str2double(get(handles.movingaveragebox, 'String'));
        filteredratios = NaN(size(ratios));
        for i=1:size(ratios, 2)
            filteredratios(:, i) = movingaveragefilterwithoutnan(ratios(:, i), movingaverage);
        end
        
        if ~isempty(framex) && numel(framex) > 1 && ~isempty(framey) && numel(framey) > 1
            
            if strcmp(selectedname, char(ones(1,5)*45))
                if strcmp(questdlg('You must select a region whose movement you are interested in to be able to plot the speed alongside the ratios. Proceed without plotting speed?','No region selected for speed measurements','Proceed','Cancel','Proceed'),'Cancel')
                    return;
                end
                currentspeed = NaN(1, nf);
            else
                currentregionx = NaN(1, nf);
                currentregiony = NaN(1, nf);
                for i=1:size(regionname, 1) %frame
                    for j=1:size(regionname, 2) %region id within the frame
                        if strcmp(char(regionname(i, j, :)), char(selectedname))
                            currentregionx(i) = rightregionx(i, j);
                            currentregiony(i) = rightregiony(i, j);
                            continue;
                        end
                    end
                end
                currentregionx(currentregionx == 0) = NaN;
                currentregiony(currentregiony == 0) = NaN;
                
                %these coefficients were extracted from the beads movies
                regionxtoactualx = -0.6277; %-0.6289;
                regionytoactualx = -0.0110; %-0.0077;
                regionxtoactualy = -0.0271; %-0.0148;
                regionytoactualy = +0.6427; %+0.6389;
                
                actualx = framex + regionxtoactualx*currentregionx + regionytoactualx*currentregiony;
                actualy = framey + regionxtoactualy*currentregionx + regionytoactualy*currentregiony;
                
                currentdisplacement = [NaN hypot(diff(actualx), diff(actualy))];
                currentdeltatime = [NaN, diff(frametime)];
                
                currentdeltatime = currentdeltatime / 1000; %converting ms to s
                
                currentspeed = currentdisplacement./currentdeltatime;
                %currentspeed(currentspeed>700) = NaN; %don't display the occasional huge speed value that may be due to fluctuations
            end
            
            filteredspeed = movingaveragefilterwithoutnan(currentspeed, movingaverage);
            
        %TODO: could add an option enabling the user to specify that the stage is stationary
            
        else
            
            filteredspeed = NaN(1, nf);
            
        end
        
        if movingaverage > 1
            linewidth = 2;
        else
            linewidth = 1;
        end
        
        if nf > 1
            figure;
            if ~usingbehaviour || numberofregionsfound > 1 %plotting normally
                hold all;
                if ~all(isnan(filteredspeed))
                    plot(1:nf, filteredspeed);
                    for i=1:numberofregionsfound
                        currentratios = filteredratios(:,i);
                        currentratios = currentratios - mean(currentratios(~isnan(currentratios)));
                        currentratios = currentratios / range(currentratios) * range(filteredspeed);
                        currentratios = currentratios + mean(filteredspeed(~isnan(filteredspeed)));
                        if any(currentratios < 0)
                            currentratios = currentratios + abs(min(currentratios(~isnan(currentratios))));
                        end
                        plot(1:nf, currentratios, 'LineWidth', linewidth);
                    end
                    legend([squeeze(selectedname)' ' speed'; char(rationames(1:numberofregionsfound, :)) repmat(' ratio', numberofregionsfound, 1)]);
                    ylabel({'Speed (um/s)', 'rescaled YFP/CFP ratios'}, 'FontSize', 12);
                else
                    plot(1:nf,filteredratios(:,1:numberofregionsfound), 'LineWidth', linewidth);
                    legend([char(rationames(1:numberofregionsfound, :)) repmat(' ratio', numberofregionsfound, 1)]);
                    ylabel('YFP/CFP Ratios', 'FontSize', 12);
                end
            else %plotting behaviour
                hold on;
                currentbehaviour = behaviour(1);
                behaviourfrom = 1;
                if ~all(isnan(filteredspeed))
                    plot(1:nf, filteredspeed, 'c');
                    currentratios = filteredratios(:,1);
                    currentratios = currentratios - mean(currentratios(~isnan(currentratios)));
                    currentratios = currentratios / range(currentratios) * range(filteredspeed);
                    currentratios = currentratios + mean(filteredspeed(~isnan(filteredspeed)));
                    if any(currentratios < 0)
                        currentratios = currentratios + abs(min(currentratios(~isnan(currentratios))));
                    end
                else
                    currentratios = filteredratios(:,1);
                end
                
                for i=1:nf
                    if (behaviour(i) ~= currentbehaviour || i == nf) && i>behaviourfrom %draw it if switching to another colour or at the end
                        switch currentbehaviour
                            case 1
                                behaviourcolour = 'k';
                            case 2
                                behaviourcolour = 'g';
                            case 3
                                behaviourcolour = 'b';
                            case 4
                                behaviourcolour = 'r';
                            case 5
                                behaviourcolour = 'y';
                            case 6
                                behaviourcolour = 'c';
                            case 7
                                behaviourcolour = 'm';
                        end
                        plot(behaviourfrom:i-1, currentratios(behaviourfrom:i-1), behaviourcolour, 'LineWidth', linewidth)
                        currentbehaviour = behaviour(i);
                        behaviourfrom = i;
                    end
                end
                if ~all(isnan(filteredspeed))
                    legend([squeeze(selectedname)' ' speed'; char(rationames(1:numberofregionsfound, :)) repmat(' ratio', numberofregionsfound, 1)]);
                    ylabel({'Speed (um/s)', 'rescaled YFP/CFP ratios'}, 'FontSize', 12);
                else
                    legend([char(rationames(1:numberofregionsfound, :)) repmat(' ratio', numberofregionsfound, 1)]);
                    ylabel('YFP/CFP Ratios', 'FontSize', 12);
                end
            end
            title(file,'Interpreter','none');
            xlabel('Frame', 'Fontsize', 12);
        else
            fprintf('NAME: %s ; RATIO= %.2f ; LEFT= %.0f ; RIGHT= %.0f\n', char(regionname(1, 1, :)), ratios(1, 1), leftvalues(1, 1), rightvalues(1, 1));
        end
    end

    function plotchannels(hobj, eventdata) %#ok<INUSD>
        leftvalues(leftvalues == 0) = NaN;
        rightvalues(rightvalues == 0) = NaN;
        
        movingaverage = str2double(get(handles.movingaveragebox, 'String'));
        filteredleft = NaN(size(leftvalues));
        for i=1:size(leftvalues, 2)
            filteredleft(:, i) = movingaveragefilterwithoutnan(leftvalues(:, i), movingaverage);
        end
        filteredright = NaN(size(rightvalues));
        for i=1:size(rightvalues, 2)
            filteredright(:, i) = movingaveragefilterwithoutnan(rightvalues(:, i), movingaverage);
            filteredright(:, i) = (filteredright(:, i) - mean(filteredright(~isnan(filteredright(:, i)), i))) ./ std(filteredright(~isnan(filteredright(:, i)), i)) .* std(filteredleft(~isnan(filteredleft(:, i)), i)) + mean(filteredleft(~isnan(filteredleft(:, i)), i)); %normalizing the other channel so that the two can be overlaid
        end
        if get(handles.channelchooser, 'Value') == 1
            yfprescaled = '';
            cfprescaled = 'rescaled ';
        elseif get(handles.channelchooser, 'Value') == 2
            yfprescaled = 'Rescaled ';
            cfprescaled = '';
        end
        
        figure; hold on;
        if (numberofregionsfound > 1)
            if get(handles.channelchooser, 'Value') == 1
                plot(1:nf,[filteredleft(:,1:numberofregionsfound) filteredright(:,1:numberofregionsfound)]);
            elseif get(handles.channelchooser, 'Value') == 2
                plot(1:nf,[filteredright(:,1:numberofregionsfound) filteredleft(:,1:numberofregionsfound)]);
            end
        else
            if get(handles.channelchooser, 'Value') == 1
                plot(1:nf, filteredleft(:,1), '-y');
                plot(1:nf, filteredright(:,1), '-c');
            elseif get(handles.channelchooser, 'Value') == 2
                plot(1:nf, filteredright(:,1), '-y');
                plot(1:nf, filteredleft(:,1), '-c');
            end
            set(gca, 'Color', [0.831 0.816 0.784]); %brown
        end
        title(file,'Interpreter','none');
        xlabel('Frame');
        ylabel(sprintf('%sYFP, and %sCFP signals', yfprescaled, cfprescaled));
        legend([char(rationames(1:numberofregionsfound, :)) repmat(' YFP', numberofregionsfound, 1);char(rationames(1:numberofregionsfound, :)) repmat(' CFP', numberofregionsfound, 1)]);
    end

    function plottogether(hobj, eventdata) %#ok<INUSD>
        ratios(ratios == 0) = NaN;
        leftvalues(leftvalues == 0) = NaN;
        rightvalues(rightvalues == 0) = NaN;
        
        movingaverage = str2double(get(handles.movingaveragebox, 'String'));
        filteredratios = NaN(size(ratios));
        for i=1:size(ratios, 2)
            filteredratios(:, i) = movingaveragefilterwithoutnan(ratios(:, i), movingaverage);
        end
        filteredleft = NaN(size(leftvalues));
        for i=1:size(leftvalues, 2)
            filteredleft(:, i) = movingaveragefilterwithoutnan(leftvalues(:, i), movingaverage);
        end
        filteredright = NaN(size(rightvalues));
        for i=1:size(rightvalues, 2)
            filteredright(:, i) = movingaveragefilterwithoutnan(rightvalues(:, i), movingaverage);
        end
        
        ratioscalingfactor = max((mean(leftvalues(~isnan(leftvalues))) + mean(rightvalues(~isnan(rightvalues)))) / 2 / mean(ratios(~isnan(ratios))), 1.0);
        %ratioscalingfactor = floor(ratioscalingfactor/(10^floor(log10(ratioscalingfactor))))*(10^floor(log10(ratioscalingfactor))); %rounds down to only one significant figure
        figure; hold on;
        if (numberofregionsfound > 1)
            if get(handles.channelchooser, 'Value') == 1
                plot(1:nf,[filteredratios(:,1:numberofregionsfound)*ratioscalingfactor filteredleft(:,1:numberofregionsfound) filteredright(:,1:numberofregionsfound)]);
            elseif get(handles.channelchooser, 'Value') == 2
                plot(1:nf,[filteredratios(:,1:numberofregionsfound)*ratioscalingfactor filteredright(:,1:numberofregionsfound) filteredleft(:,1:numberofregionsfound)]);
            end
            legend([char(rationames(1:numberofregionsfound, :)) repmat(' ratio', numberofregionsfound, 1); char(rationames(1:numberofregionsfound, :)) repmat(' YFP  ', numberofregionsfound, 1); char(rationames(1:numberofregionsfound, :)) repmat(' CFP  ', numberofregionsfound, 1)]);
        else
            if get(handles.channelchooser, 'Value') == 1
                plot(1:nf,filteredleft(:,1), '-y');
                plot(1:nf,filteredright(:,1), '-c');
            elseif get(handles.channelchooser, 'Value') == 2
                plot(1:nf,filteredright(:,1), '-y');
                plot(1:nf,filteredleft(:,1), '-c');
            end
            plot(1:nf,filteredratios(:,1)*ratioscalingfactor, '-r');
            set(gca, 'Color', [0.831 0.816 0.784]); %brown
            legend([char(rationames(1, :)) ' YFP  '; char(rationames(1, :)) ' CFP  '; char(rationames(1, :)) ' ratio']);
        end
        title(file,'Interpreter','none');
        xlabel('Frame');
        ylabel({sprintf('YFP/CFP ratios * %.0f', ratioscalingfactor);'YFP and CFP signals'});
    end

    function plotposition (hobj, eventdata) %#ok<INUSD>
        %Showing ratio based on position (not frame number)
        referenceratio = NaN(subchannelsizey, subchannelsizex);
        for i=1:nf
            for j=1:numberofregions(i)
                for k=1:numberofregionsfound
                    if (strcmp(char(regionname(i,j,:)), char(rationames(k,:))) == 1)
                        if get(handles.channelchooser, 'Value') == 1
                            referenceratio(leftregiony(i,j), leftregionx(i,j)) = (leftvalues(i,k)/rightvalues(i,k)-correctionfactorA) * correctionfactorB;
                        elseif get(handles.channelchooser, 'Value') == 2
                            referenceratio(rightregiony(i,j), rightregionx(i,j)) = (rightvalues(i,k)/leftvalues(i,k)-correctionfactorA) * correctionfactorB;
                        end
                        break;
                    end
                end
            end
        end
        figure; imshow(referenceratio, []); colormap(jet); colorbar;
        title(file,'Interpreter','none');
        xlabel('x-position (pixel)');
        ylabel('y-position (pixel)');
    end

    function findnextregion(hobj, eventdata)
        foundanunnamed = false;
        for i = get(handles.frame, 'Value'):nf
            jfrom = 1;
            if selectedregion > 0 && ~isinf(selectedregion) && i == get(handles.frame, 'Value')
                jfrom = selectedregion;
            end

            for j=jfrom:numberofregions(i)
                if strcmp(char(regionname(i, j, :)), selectedname)
                    continue;
                end
                alreadynamed = false;
                for k=1:5
                    if regionname(i,j,k) ~= 32 && regionname(i,j,k) ~= 45 && (regionname(i,j,k) < 48 || regionname(i,j,k) > 57) %if it contains something other than a space, a dash, or a number, i.e. if it's not named manually yet
                        alreadynamed = true;
                        break
                    end
                end
                if ~alreadynamed
                    foundanunnamed = true;
                    break;
                end
            end
            if foundanunnamed
                break;
            end
        end
        if foundanunnamed
            frame = i;
            set(handles.frame,'Value', i);
            selectedregion = j;
            updateselection;
            showframe(hobj, eventdata);
        else
            fprintf('Warning: could not find any unnamed region for selection. Keeping previously selected region.\n');
        end
    end

    function selectregion(hobj,eventdata)
        if numberofregions(frame) == 0
            fprintf('Warning: could not find a region for selection. Deselecting.\n');
            clearselection;
            showframe(hobj, eventdata);
        elseif numberofregions(frame) == 1
            selectedregion = 1;
            updateselection;
            showframe(hobj, eventdata); %showframe because the selected region may have changed, and in that case we need to highlight the new region
        else
            previouschannelvalue = get(handles.channel, 'Value');
            needsrefresh = false;
            if (previouschannelvalue < 4 || previouschannelvalue > 7)
                if get(handles.channelchooser, 'Value') == 1
                    set(handles.channel, 'Value', 4);
                    selectingfromleft = true;
                elseif get(handles.channelchooser, 'Value') == 2
                    set(handles.channel, 'Value', 5);
                    selectingfromleft = false;
                end
                needsrefresh = true;
            elseif (previouschannelvalue == 4 || previouschannelvalue == 6)
                selectingfromleft = true;
            else %if (previouschannelvalue == 5 || previouschannelvalue == 7)
                selectingfromleft = false;
            end
            %{
            set(controlselectregion, 'Enable', 'off');
            set(controladjustregion, 'Enable', 'off');
            set(handles.channel, 'Enable', 'off');
            set(handles.frame, 'Enable', 'off');
            set(handles.makefigure, 'Enable', 'off');
            set(handles.plusfifty, 'Enable', 'off');
            set(handles.minusfifty, 'Enable', 'off');
            %}

            if needsrefresh
                showframe(hobj, eventdata);
            end
            
            disableeverythingtemp;
            
            [x, y] = zinput('crosshair', 'Color', 'r');
            bestdistance = Inf;
            bestwhich = NaN;
            if (numberofregions(frame) > 0 && x >= 1 && x <= subchannelsizex && y >= 1 && y <= subchannelsizey)
                for j=1:numberofregions(frame)
                    if (selectingfromleft)
                        currentdistance = (leftregionx(frame,j)-x)^2 + (leftregiony(frame, j)-y)^2;
                        if (currentdistance < bestdistance)
                            bestdistance = currentdistance;
                            bestwhich = j;
                        end
                    else
                        currentdistance = (rightregionx(frame,j)-x)^2 + (rightregiony(frame, j)-y)^2;
                        if (currentdistance < bestdistance)
                            bestdistance = currentdistance;
                            bestwhich = j;
                        end
                    end
                end
            end
            if ~isnan(bestwhich)
    %            disp('found something!');
                selectedregion = bestwhich;
                updateselection;
            else
                fprintf('Warning: could not find a region for selection. Keeping previously selected region.\n');
            end
            %{
            set(controlselectregion, 'Enable', 'on');
            set(controladjustregion, 'Enable', 'on');
            set(handles.channel, 'Enable', 'on');
            set(handles.frame, 'Enable', 'on');
            set(handles.makefigure, 'Enable', 'on');
            set(handles.plusfifty, 'Enable', 'on');
            set(handles.minusfifty, 'Enable', 'on');
            %}
            updatevisibility;
            if needsrefresh
                set(handles.channel, 'Value', previouschannelvalue);
            end
            showframe(hobj, eventdata); %showframe because the selected region may have changed, and in that case we need to highlight the new region
        end
    end

    function adjustarb (hobj,eventdata)
        if ~any(arbarea(:))
            questdlg('You must first add an arbitrary region before it can be adjusted.', 'Adjusting arbitrary region', 'OK', 'OK');
            return;
        end
        if selectedregion == 0
            questdlg('You must first select a regular region on which to base the adjustment for the arbitrary region.', 'Adjusting arbitrary region', 'OK', 'OK');
            return;
        end
        if get(handles.channel, 'Value') < 4 || get(handles.channel, 'Value') > 7
            questdlg('You must first choose whether to adjust based on the left or the right coordinates of the regular region by selecting the appropriate channel view.', 'Adjusting arbitrary region', 'OK', 'OK');
            return;
        end
        if get(handles.channel, 'Value') == 4 || get(handles.channel, 'Value') == 6
            useleft = true;
        else
            useleft = false;
        end
        [ifrom, ito, doall] = fromto; %#ok<NASGU>
        for i=ifrom:ito
            foundregular = false;
            for j=1:numberofregions(i)
                if strcmp(char(regionname(i,j,:)), selectedname)
                    foundregular = true;
                    if useleft
                        adjustx = leftregionx(i, j) - leftregionx(frame, selectedregion);
                        adjusty = leftregiony(i, j) - leftregiony(frame, selectedregion);
                    else
                        adjustx = rightregionx(i, j) - rightregionx(frame, selectedregion);
                        adjusty = rightregiony(i, j) - rightregiony(frame, selectedregion);
                    end
                    break
                end
            end
            if foundregular
                if adjustx > 0
                    arbarea(i, :, :) = [false(subchannelsizey, adjustx) squeeze(arbarea(i, :, 1:end-adjustx))];
                elseif adjustx < 0
                    arbarea(i, :, :) = [squeeze(arbarea(i, :, 1+abs(adjustx):end)) false(subchannelsizey, abs(adjustx))];
                end
                if adjusty > 0
                    arbarea(i, :, :) = [false(adjusty, subchannelsizex); squeeze(arbarea(i, 1:end-adjusty, :))];
                elseif adjusty < 0
                    arbarea(i, :, :) = [squeeze(arbarea(i, 1+abs(adjusty):end, :)); false(abs(adjusty), subchannelsizex)];
                end
            else
                arbarea(i, :, :) = false(subchannelsizey, subchannelsizex);
            end
        end
        
        showframe(hobj, eventdata);
    end

    function displaceboth(hobj,eventdata)
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue < 4 || previouschannelvalue > 7)
            if get(handles.channelchooser, 'Value') == 1
                set(handles.channel, 'Value', 4);
                selectingfromleft = true;
            elseif get(handles.channelchooser, 'Value') == 2
                set(handles.channel, 'Value', 5);
                selectingfromleft = false;
            end
            needsrefresh = true;
        elseif (previouschannelvalue == 4 || previouschannelvalue == 6)
            selectingfromleft = true;
        else %if (previouschannelvalue == 5 || previouschannelvalue == 7)
            selectingfromleft = false;
        end
        %{
        set(controlselectregion, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        set(handles.channel, 'Enable', 'off');
        set(handles.frame, 'Enable', 'off');
        set(handles.setframe, 'Enable', 'off');
        set(handles.makefigure, 'Enable', 'off');
        set(handles.plusfifty, 'Enable', 'off');
        set(handles.minusfifty, 'Enable', 'off');
        %}
        if needsrefresh
            showframe(hobj, eventdata);
        end
        disableeverythingtemp;
        if selectingfromleft
            selectionradius = leftregionradius(get(handles.frame, 'Value'),selectedregion);
            originalx = leftregionx(get(handles.frame, 'Value'), selectedregion);
            originaly = leftregiony(get(handles.frame, 'Value'), selectedregion);
        else
            selectionradius = rightregionradius(get(handles.frame, 'Value'),selectedregion);
            originalx = rightregionx(get(handles.frame, 'Value'), selectedregion);
            originaly = rightregiony(get(handles.frame, 'Value'), selectedregion);
        end
        [x, y, clicktype] = zinput('circle', 'xradius', selectionradius*radius, 'yradius', selectionradius*radius, 'Colour', 'r', 'keeplimits', true);
        if strcmp(clicktype, 'normal')
            displacementx = x - originalx;
            displacementy = y - originaly;
            if x >= 1 && x <= subchannelsizex && y >= 1 && y <= subchannelsizey
                [ifrom, ito, doall] = fromto;
                for i=ifrom:ito
                    for j=1:numberofregions(i)
                        if (doall || strcmp(char(regionname(i,j,:)), selectedname))
                            leftmovedtox = round(leftregionx(i,j) + displacementx);
                            leftmovedtoy = round(leftregiony(i,j) + displacementy);
                            rightmovedtox = round(rightregionx(i,j) + displacementx);
                            rightmovedtoy = round(rightregiony(i,j) + displacementy);
                            wentoutofbounds = false;
                            if leftmovedtox < 1
                                leftmovedtox = 1;
                                wentoutofbounds = true;
                            end
                            if leftmovedtoy < 1
                                leftmovedtoy = 1;
                                wentoutofbounds = true;
                            end
                            if rightmovedtox < 1
                                rightmovedtox = 1;
                                wentoutofbounds = true;
                            end
                            if rightmovedtoy < 1
                                rightmovedtoy = 1;
                                wentoutofbounds = true;
                            end
                            if leftmovedtox > subchannelsizex
                                leftmovedtox = subchannelsizex;
                                wentoutofbounds = true;
                            end
                            if rightmovedtox > subchannelsizex
                                rightmovedtox = subchannelsizex;
                                wentoutofbounds = true;
                            end
                            if leftmovedtoy > subchannelsizey
                                leftmovedtoy = subchannelsizey;
                                wentoutofbounds = true;
                            end
                            if rightmovedtoy > subchannelsizey
                                rightmovedtoy = subchannelsizey;
                                wentoutofbounds = true;
                            end
                            leftregionx(i, j) = leftmovedtox;
                            leftregiony(i, j) = leftmovedtoy;
                            rightregionx(i, j) = rightmovedtox;
                            rightregiony(i, j) = rightmovedtoy;
                            if wentoutofbounds
                                fprintf('Warning: the position of region ''%s'' would be displaced outside of the channel boundaries in frame %d. Keeping it at the boundary instead.\n', strtrim(char(squeeze(regionname(i,j,:))')), i);
                            end
                        end
                    end
                end
                updateselection;
            else
                fprintf('Warning: chosen position is out of bounds. Keeping previous position.\n');
            end
        end
        %{
        set(controlselectregion, 'Enable', 'on');
        set(controladjustregion, 'Enable', 'on')
        set(handles.channel, 'Enable', 'on');
        set(handles.frame, 'Enable', 'on');
        set(handles.setframe, 'Enable', 'on');
        set(handles.makefigure, 'Enable', 'on');
        set(handles.plusfifty, 'Enable', 'on');
        set(handles.minusfifty, 'Enable', 'on');
        %}
        updatevisibility;
        if needsrefresh
            set(handles.channel, 'Value', previouschannelvalue);
        end
        showframe(hobj, eventdata);
    end

    function adjustleft(hobj,eventdata)
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue ~= 4)
            set(handles.channel, 'Value', 4);
            needsrefresh = true;
        end
        %{
        set(controlselectregion, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        set(handles.channel, 'Enable', 'off');
        set(handles.frame, 'Enable', 'off');
        set(handles.setframe, 'Enable', 'off');
        set(handles.makefigure, 'Enable', 'off');
        set(handles.plusfifty, 'Enable', 'off');
        set(handles.minusfifty, 'Enable', 'off');
        %}
        if needsrefresh
            showframe(hobj, eventdata);
        end
        disableeverythingtemp;
        [x, y] = zinput('circle', 'xradius', leftregionradius(get(handles.frame, 'Value'),selectedregion)*radius, 'yradius', leftregionradius(get(handles.frame, 'Value'),selectedregion)*radius, 'Colour', 'r', 'keeplimits', true);
        if x >= 1 && x <= subchannelsizex && y >= 1 && y <= subchannelsizey
            [ifrom, ito, doall] = fromto;
            for i=ifrom:ito
                for j=1:numberofregions(i)
                    if (doall || strcmp(char(regionname(i,j,:)), selectedname))
                        leftregionx(i, j) = round(x);
                        leftregiony(i, j) = round(y);
                    end
                end
            end
            updateselection;
        else
            fprintf('Warning: chosen position is out of bounds. Keeping previous position.\n');
        end
        %{
        set(controlselectregion, 'Enable', 'on');
        set(controladjustregion, 'Enable', 'on')
        set(handles.channel, 'Enable', 'on');
        set(handles.frame, 'Enable', 'on');
        set(handles.setframe, 'Enable', 'on');
        set(handles.makefigure, 'Enable', 'on');
        set(handles.plusfifty, 'Enable', 'on');
        set(handles.minusfifty, 'Enable', 'on');
        %}
        updatevisibility;
        if needsrefresh
            set(handles.channel, 'Value', previouschannelvalue);
        end
        showframe(hobj, eventdata);
    end

    function adjustright(hobj,eventdata)
        previouschannelvalue = get(handles.channel, 'Value');
        needsrefresh = false;
        if (previouschannelvalue ~= 5)
            set(handles.channel, 'Value', 5);
            needsrefresh = true;
        end
        %{
        set(controlselectregion, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        set(handles.channel, 'Enable', 'off');
        set(handles.frame, 'Enable', 'off');
        set(handles.setframe, 'Enable', 'off');
        set(handles.makefigure, 'Enable', 'off');
        set(handles.plusfifty, 'Enable', 'off');
        set(handles.minusfifty, 'Enable', 'off');
        %}
        if needsrefresh
            showframe(hobj, eventdata);
        end
        disableeverythingtemp;
        [x, y] = zinput('circle', 'xradius', rightregionradius(get(handles.frame, 'Value'),selectedregion)*radius, 'yradius', rightregionradius(get(handles.frame, 'Value'),selectedregion)*radius, 'Colour', 'r', 'keeplimits', true);
        if x >= 1 && x <= subchannelsizex && y >= 1 && y <= subchannelsizey
            [ifrom, ito, doall] = fromto;
            for i=ifrom:ito
                for j=1:numberofregions(i)
                    if (doall || strcmp(char(regionname(i,j,:)), selectedname))
                        rightregionx(i, j) = round(x);
                        rightregiony(i, j) = round(y);
                    end
                end
            end
            updateselection;
        else
            fprintf('Warning: chosen position is out of bounds. Keeping previous position.\n');
        end
        %{
        set(controlselectregion, 'Enable', 'on');
        set(controladjustregion, 'Enable', 'on');
        set(handles.channel, 'Enable', 'on');
        set(handles.frame, 'Enable', 'on');
        set(handles.setframe, 'Enable', 'on');
        set(handles.makefigure, 'Enable', 'on');
        set(handles.plusfifty, 'Enable', 'on');
        set(handles.minusfifty, 'Enable', 'on');
        %}
        updatevisibility;
        if needsrefresh
            set(handles.channel, 'Value', previouschannelvalue);
        end
        showframe(hobj, eventdata);
    end

    function adjustleftradius(hobj, eventdata)
        tempnewleftradius = str2double(get(handles.leftradiusdisplay, 'String'));
        if ~isnan(tempnewleftradius)
            tempnewleftradius = bound(tempnewleftradius, 1, [subchannelsizex subchannelsizey]);
            [ifrom, ito, doall] = fromto;
            for i=ifrom:ito
                for j=1:numberofregions(i)
                    if (doall || strcmp(char(regionname(i,j,:)), selectedname))
                        leftregionradius(i, j) = tempnewleftradius;
                    end
                end
            end
        else
            fprintf('Warning: inappropriate value for left region radius. Keeping previous radius.\n');
        end
		updateselection;
		showframe(hobj, eventdata);
    end

    function adjustrightradius(hobj, eventdata)
        tempnewrightradius = str2double(get(handles.rightradiusdisplay, 'String'));
        if ~isnan(tempnewrightradius)
            tempnewrightradius = bound(tempnewrightradius, 1, [subchannelsizex, subchannelsizey]);
            [ifrom, ito, doall] = fromto;
            for i=ifrom:ito
                for j=1:numberofregions(i)
                    if (doall || strcmp(char(regionname(i,j,:)), selectedname))
                        rightregionradius(i, j) = tempnewrightradius;
                    end
                end
            end
        else
            fprintf('Warning: inappropriate value for right region radius. Keeping previous radius.\n');
        end
		updateselection;
		showframe(hobj, eventdata);
    end

    function adjustapplyfrom (hobj, eventdata) %#ok<INUSD>
        tempnewapplyfrom = round(str2double(get(handles.applyfrom, 'String')));
        if isnan(tempnewapplyfrom)
            tempnewapplyfrom = 1;
        end
        tempnewapplyfrom = bound(tempnewapplyfrom, 1, nf);
        if tempnewapplyfrom > round(str2double(get(handles.applyto, 'String'))) %if start would be larger than end, set end to start
            set(handles.applyto, 'String', num2str(tempnewapplyfrom));
        end
        set(handles.applyfrom, 'String', num2str(tempnewapplyfrom));
    end

    function adjustapplyto (hobj, eventdata) %#ok<INUSD>
        tempnewapplyto = round(str2double(get(handles.applyto, 'String')));
        if isnan(tempnewapplyto)
            tempnewapplyto = nf;
        end
        tempnewapplyto = bound(tempnewapplyto, 1, nf);
        if tempnewapplyto < round(str2double(get(handles.applyfrom, 'String'))) %if end would be smaller than start, set start to end
            set(handles.applyfrom, 'String', num2str(tempnewapplyto));
        end
        set(handles.applyto, 'String', num2str(tempnewapplyto));
    end

    function preserveapply
        switch (get(handles.applypreset, 'Value'))
            case 1
                set(handles.applyfrom, 'String', 1);
                set(handles.applyto, 'String', get(handles.frame, 'Value'));
            case 2
                set(handles.applyfrom, 'String', get(handles.frame, 'Value'));
                set(handles.applyto, 'String', get(handles.frame, 'Value'));
            case 3
                set(handles.applyfrom, 'String', get(handles.frame, 'Value'));
                set(handles.applyto, 'String', nf);
            case 4
                set(handles.applyfrom, 'String', 1);
                set(handles.applyto, 'String', nf);
            case 5
                set(handles.applyfrom, 'String', 1);
                set(handles.applyto, 'String', nf);
            % shouldn't update when set to manual (6)
        end
    end

    %Find the region ID of the selected region name
    function preserveselection
        if selectedregion ~= 0 %if there is nothing to preserve, do nothing
            selectedregion = 0; % by default, could not find the same region in this frame; if found, it will be overwritten
            for j=1:numberofregions(frame)
                if strcmp(char(regionname(frame, j, :)), selectedname)
                    selectedregion = j;
                    break;
                end
            end
            if selectedregion == 0
                clearselection;
            else
                updateselection;
            end
        end
    end

    function updateselection
        if numberofregions(frame) >= selectedregion && selectedregion ~= 0
            selectedname = char(regionname(frame, selectedregion,:));
            selectedradiusy = leftregionradius(frame, selectedregion);
            selectedradiusc = rightregionradius(frame, selectedregion);
            set(handles.regionnamedisplay,'String',selectedname);
            set(handles.regionnametext,'String',['Region name (' num2str(selectedregion) ')']);
            set(handles.measureregion,'Value', regionimportant(frame, selectedregion));
            set(handles.adjustleft,'String',['Left (' num2str(leftregionx(frame, selectedregion)) ';' num2str(leftregiony(frame, selectedregion)) ')']);
            set(handles.adjustright,'String',['Right (' num2str(rightregionx(frame, selectedregion)) ';' num2str(rightregiony(frame, selectedregion)) ')']);
            set(handles.leftradiusdisplay,'String', num2str(selectedradiusy));
            set(handles.rightradiusdisplay,'String', num2str(selectedradiusc));
            currentlyselected = true;
            if ~currentlycalculating
                canadjustregion = true;
                set(controladjustregion,'Enable','on'); %cannot call updatevisibility as that would enable buttons that should not be enabled during calculation
            end
        else
            fprintf('Warning: selected region index (%d) is out of bounds in frame %d, which has %d regions.\n', selectedregion, frame, numberofregions(frame));
        end
    end

    function setmeasureregion(hobj, eventdata) %#ok<INUSD>
        [ifrom, ito, doall] = fromto;
        for i=ifrom:ito
            for j=1:numberofregions(i)
                if doall || (strcmp(char(regionname(i, j, :)), selectedname) == 1)
                    regionimportant(i, j) = get(handles.measureregion, 'Value');
                    
                    if get(handles.measureregion, 'Value') == 0 %If the region is being set to being unimportant, and results were calculated for it, remove these results immediately, so that it won't be necessary to recalculate just for removing things
                        
                        for k=1:numberofregionsfound
                            if doall || (strcmp(selectedname, char(rationames(k,:))) == 1)
                                leftvalues(i,k) = NaN;
                                rightvalues(i,k) = NaN;
                                leftbackground(i,k) = NaN;
                                rightbackground(i,k) = NaN;
                                ratios(i,k) = NaN;
                                if ~doall
                                    break;
                                end
                            end
                        end
                        
                    end
                    
                end
            end
        end
        
        if get(handles.measureregion, 'Value') == 0 %The region might be completely unimportant, in which case we move the last stored region to overwrite this
            for k=numberofregionsfound:-1:1 %find the id of the selected region among the results
                if doall || (strcmp(selectedname, char(rationames(k,:))) == 1)
                    removeifempty(k);
                    if ~doall
                        break;
                    end
                end
            end
        end
        
    end

    function setbehaviour(hobj, eventdata) %#ok<INUSD>
        [ifrom, ito, doall] = fromto; %#ok<NASGU>
        for i=ifrom:ito
            behaviour(i) = get(handles.behaviourpopup, 'Value');
        end
        if any(behaviour ~= CONST_BEHAVIOUR_UNKNOWN & behaviour ~= CONST_BEHAVIOUR_BADFRAME)
            usingbehaviour = true;
        else
            usingbehaviour = false;
        end
    end
    
    function updatebehaviour(hobj, eventdata) %#ok<INUSD>
        set(handles.behaviourpopup, 'Value', behaviour(get(handles.frame, 'Value')));
    end
    
    function updatechannelchooser(hobj, eventdata) %#ok<INUSD>
        if get(handles.channelchooser, 'Value') == 3
            set([handles.correctionfactorAtext handles.correctionfactorA handles.correctionfactorBtext handles.correctionfactorB], 'Visible', 'off', 'Enable', 'off');
            set(handles.plotratios, 'String', 'Plot intensities');
            set(handles.plotchannels, 'Visible', 'off');
            set(handles.plottogether, 'Visible', 'off');
            set(handles.leftthresholdtext, 'String', 'Threshold');
            set(handles.rightthresholdtext, 'Visible', 'off');
            set(handles.rightthresholdbox, 'Visible', 'off');
        else
            set([handles.correctionfactorAtext handles.correctionfactorA handles.correctionfactorBtext handles.correctionfactorB], 'Visible', 'on', 'Enable', 'on');
            set(handles.plotratios, 'String', 'Plot ratios');
            set(handles.plotchannels, 'Visible', 'on');
            set(handles.plottogether, 'Visible', 'on');
            set(handles.leftthresholdtext, 'String', 'Left threshold');
            set(handles.rightthresholdtext, 'Visible', 'on');
            set(handles.rightthresholdbox, 'Visible', 'on');
        end
        updatesubchannelsizes;
        showframe;
    end
    
    function setregionname(hobj, eventdata)
        oldname = selectedname;
        if ~strcmp(oldname, char(regionname(frame, selectedregion,:)))
			fprintf('Warning: mismatch between stored selected name, and the name of the selected region at the current frame. Stored name = %s . Calculated name = %s .\n', oldname, char(regionname(frame, selectedregion,:))); 
        end
        tempnewname = get(handles.regionnamedisplay,'String');
        tempnewname = tempnewname(1,1:min(end,5));
        if (size(tempnewname,2) < 5)
            tempnewname(1,end+1:5) = char(ones(1,5-size(tempnewname,2))*32);
        end
        %Now change the names of the regions that have had the previous name
        [ifrom, ito, doall] = fromto;
        for i=ifrom:ito
            for j=1:numberofregions(i)
                if doall || strcmp(char(regionname(i,j,:)), oldname)
                    nootherlikeit = true;
                    for k = 1:numberofregions(i)
                        if k ~= j && strcmp(char(regionname(i,k,:)), tempnewname)
                            nootherlikeit = false;
                            break;
                        end
                    end
                    if nootherlikeit
						changingfrom = 0;
						%Because it's possible that multiple neurons with different names are renamed to one (e.g. if there is only one neuron, which received different identities in different frames), or that there is a clash in some frames but not in others, it makes sense to search for the name in each frame and each region individually
						for k = 1:numberofregionsfound %Try to find if we have already calculated results for this region in this frame, and if so, change its name and values accordingly 
							if strcmp(char(regionname(i,j,:)), char(rationames(k, :))) == 1
								changingfrom = k;
								break;
							end 
						end
						if changingfrom > 0 %If we do have calculated results for this region
							changingto = 0;
							for k = 1:numberofregionsfound %Try to find if we already have a region with this name, with which we're going to merge
								if strcmp(tempnewname, char(rationames(k, :))) == 1
									changingto = k;
									break;
								end
							end
							if changingto == 0 %If the region name we're changing it to is new
								numberofregionsfound = numberofregionsfound + 1;
								changingto = numberofregionsfound;
							end
							%copying the values to the new region
							ratios(i, changingto) = ratios(i, changingfrom);
							ratios(i, changingto) = ratios(i, changingfrom);
							leftvalues(i,changingto) = leftvalues(i, changingfrom);
							rightvalues(i,changingto) = rightvalues(i,changingfrom);
							leftbackground(i,changingto) = leftbackground(i,changingfrom);
							rightbackground(i,changingto) = rightbackground(i,changingfrom);
							rationames(changingto,:) = tempnewname(:); %this ensures that if it's a new region, it receives a name. If it's not new, it will be overwritten with itself (i.e. no change) 
							%deleting values from the old region
							ratios(i, changingfrom) = NaN;
							leftvalues(i, changingfrom) = NaN;
							rightvalues(i, changingfrom) = NaN;
							leftbackground(i, changingfrom) = NaN;
							rightbackground(i, changingfrom) = NaN;
						end
                        regionname(i,j,:) = tempnewname(:);
                    else
                        fprintf('Warning: another region by the same specified name exists in the same frame. Keeping that region as it was. The problem occurred in frame %d .\n',i);
                    end
                end
            end
        end
		for j=numberofregionsfound:-1:1
			removeifempty(j, 'silently');
		end
        selectedname = char(regionname(frame, selectedregion,:));
        set(handles.regionnamedisplay,'String',selectedname);
        showframe(hobj, eventdata);
    end

    function deleteregion (hobj, eventdata)
        [ifrom, ito, doall] = fromto;
        for i=ifrom:ito
            for j=1:numberofregions(i)
                if doall || strcmp(char(regionname(i,j,:)), selectedname)
                    %First remove calculated values if they exist
                    for k=1:numberofregionsfound
                        if doall || strcmp(selectedname, char(rationames(k,:)))
                            leftvalues(i,k) = NaN;
                            rightvalues(i,k) = NaN;
                            leftbackground(i,k) = NaN;
                            rightbackground(i,k) = NaN;
                            ratios(i,k) = NaN;
                            if ~doall
                                break;
                            end
                        end
                    end
                    %Overwrite the region with the last region in the frame
                    regionname(i,j,:) = regionname(i,numberofregions(i),:);
                    leftregionx(i,j) = leftregionx(i,numberofregions(i));
                    leftregiony(i,j) = leftregiony(i,numberofregions(i));
                    rightregionx(i,j) = rightregionx(i,numberofregions(i));
                    rightregiony(i,j) = rightregiony(i,numberofregions(i));
                    leftregionradius(i,j) = leftregionradius(i,numberofregions(i));
                    rightregionradius(i,j) = rightregionradius(i,numberofregions(i));
                    %Set the last region in the frame to zero
                    regionname(i,numberofregions(i),:) = char(ones(1,5)*45); %-----
                    leftregionx(i,numberofregions(i)) = 0;
                    leftregiony(i,numberofregions(i)) = 0;
                    rightregionx(i,numberofregions(i)) = 0;
                    rightregiony(i,numberofregions(i)) = 0;
                    leftregionradius(i,numberofregions(i)) = 0;
                    rightregionradius(i,numberofregions(i)) = 0;
                    %Decrement the number of regions for this frame
                    numberofregions(i) = numberofregions(i) - 1;
                end
            end
        end
        maxnumberofexistingregions = max(max(numberofregions(:)),1); %We're not setting the maxnumberofregions to its obvious value, because making sure that maxnumberofregions doesn't decrease ensures that two regions will not be given the same name automatically (because names are based on maxnumberofregions)
        regionname = regionname(:,1:maxnumberofexistingregions,:);
        leftregionx = leftregionx(:,1:maxnumberofexistingregions);
        leftregiony = leftregiony(:,1:maxnumberofexistingregions);
        rightregionx = rightregionx(:,1:maxnumberofexistingregions);
        rightregiony = rightregiony(:,1:maxnumberofexistingregions);
        leftregionradius = leftregionradius(:,1:maxnumberofexistingregions);
        rightregionradius = rightregionradius(:,1:maxnumberofexistingregions);
        for k=numberofregionsfound:-1:1 %find the id of the selected region among the results
            if doall || strcmp(selectedname, char(rationames(k,:)))
                removeifempty(k);
                if ~doall
                    break;
                end
            end
        end
        
        clearselection;
        
        showframe(hobj, eventdata);
    end

	function removeifempty (which, how)
		if sum(~isnan(ratios(:,which))) == 0 %if there are no results for it, overwrite it with the last important region. The results of the region in question have then been set to NaN already, so no need to clear it here again
			if ~(exist('how', 'var') == 1 && (strcmpi(how, 'silently') == 1 || strcmpi(how, 'silent') == 1))
				fprintf('Cleared the results for region %s completely.\n', char(rationames(which,:)));
			end
			ratios(:,which) = ratios(:,numberofregionsfound);
			leftvalues(:,which) = leftvalues(:,numberofregionsfound);
			rightvalues(:,which) = rightvalues(:,numberofregionsfound);
			leftbackground(:,which) = leftbackground(:,numberofregionsfound);
			rightbackground(:,which) = rightbackground(:,numberofregionsfound);
			rationames(which,:) = rationames(numberofregionsfound, :);
			numberofregionsfound = numberofregionsfound - 1;
			if numberofregionsfound < 0
				numberofregionsfound = 0;
			end
			if numberofregionsfound == 0
				canplot = false;
				canmanipulate = false;
				updatevisibility;
            else
                ratios = ratios(:,1:numberofregionsfound);
                leftvalues = leftvalues(:,1:numberofregionsfound);
                rightvalues = rightvalues(:,1:numberofregionsfound);
                leftbackground = leftbackground(:,1:numberofregionsfound);
                rightbackground = rightbackground(:,1:numberofregionsfound);
                rationames = rationames(1:numberofregionsfound, :);
			end
		end
    end

    function addregion (hobj, eventdata)
        maxnumberofregions = maxnumberofregions + 1;
        newnamestring = num2str(maxnumberofregions);
        if (size(newnamestring,2) < 5) %Const size strings enforced
            newnamestring(size(newnamestring,2)+1:5) = ones(5-size(newnamestring,2),1)*32;
        end
        [ifrom, ito] = fromto;
        for i=ifrom:ito
            numberofregions(i) = numberofregions(i)+1;
            leftregionx(i, numberofregions(i)) = round(subchannelsizex/2);
            leftregiony(i, numberofregions(i)) = round(subchannelsizey/2);
            rightregionx(i, numberofregions(i)) = round(subchannelsizex/2);
            rightregiony(i, numberofregions(i)) = round(subchannelsizey/2);
            if strcmpi(get(handles.zpos, 'Visible'), 'on')
                leftregionz(i, numberofregions(i)) = get(handles.zpos, 'Value');
                rightregionz(i, numberofregions(i)) = get(handles.zpos, 'Value');
            else
                leftregionz(i, numberofregions(i)) = 1;
                rightregionz(i, numberofregions(i)) = 1;
            end
            regionimportant(i, numberofregions(i)) = true;
            leftregionradius(i, numberofregions(i)) = 1;
            rightregionradius(i, numberofregions(i)) = 1;
            regionname(i, numberofregions(i),:) = newnamestring;
            if (i == frame)
                selectedregion = numberofregions(i);
            end
        end
        canselectregion = true;
        canadjustregion = true;
        canadjustmeasurement = true;
        canshowneurons = true;
        cancalculate = true;
        set(handles.showneurons,'Value',1);
        updateselection;
        updatevisibility;
        showframe(hobj, eventdata);
    end

    function addarb (hobj, eventdata)
        
        if stack3d && ~maxproject
            questdlg('You must use maximum projection on this 3d stack if you would like to add an arbitrary region.', 'Adding arbitrary region', 'OK', 'OK');
            return;
        end
        if get(handles.channel, 'Value') < 4 || get(handles.channel, 'Value') > 7
            questdlg('You must first choose whether to base the arbitrary region on the left or the right channel by selecting the appropriate channel view.', 'Adding arbitrary region', 'OK', 'OK');
            return;
        end
        
        hold on;
        
        if isempty(arbarea)
            arbarea = false(nf, subchannelsizey, subchannelsizex);
        end
        [meshx, meshy] = meshgrid(1:subchannelsizex,1:subchannelsizey);
        
        clicktype = 'nothing yet';
        verticesx = [];
        verticesy = [];
        while ~strcmpi(clicktype, 'alt') && ~strcmpi(clicktype, 'extend')
            if ~isempty(verticesx) && ~isempty(verticesy)
                scatter(verticesx(end), verticesy(end), [], 'm');
                if numel(verticesx) == 1
                    plot(verticesx(end), verticesy(end), '-m.');
                elseif numel(verticesx) > 1
                    plot([verticesx(end-1) verticesx(end)], [verticesy(end-1) verticesy(end)], '-m.');
                end
            end
            [x, y, clicktype] = zinput('Crosshair', 'radius', 10);
            if strcmpi(clicktype, 'normal')
                verticesx(end+1) = x; %#ok<AGROW>
                verticesy(end+1) = y; %#ok<AGROW>
            end
        end
        if strcmpi(clicktype, 'alt') %'alt' (right click) exits and APPLIES the changes; use 'extend' (middle click) to leave without any changes
            [ifrom, ito] = fromto;
            for i=ifrom:ito
                arbarea(i, :, :) = false;
                if numel(verticesx) > 1 && numel(verticesy) > 1
                    arbarea(i, inpolygon(meshx, meshy, verticesx, verticesy)) = true;
                end
            end
        end
        hold off;
        
        if any(arbarea(:))
            set(handles.showarb, 'Visible', 'on');
            canadjustmeasurement = true;
            cancalculate = true;
            updatevisibility;
        else
            set(handles.showarb, 'Visible', 'off', 'Value', 0);
        end
        
        showframe(hobj, eventdata);
    end

    function copyregion (hobj, eventdata)
        
        if selectedregion == 0
            questdlg('You must select the region you want to copy.','No region selected for copying','Ok','Ok')
            return;
        end
        
        maxnumberofregions = maxnumberofregions + 1;
        newnamestring = num2str(maxnumberofregions);
        if (size(newnamestring,2) < 5) %Const size strings enforced
            newnamestring(size(newnamestring,2)+1:5) = ones(5-size(newnamestring,2),1)*32;
        end
        [ifrom, ito] = fromto;
        for i=ifrom:ito
            numberofregions(i) = numberofregions(i)+1;
            leftregionx(i, numberofregions(i)) = leftregionx(i, selectedregion);
            leftregiony(i, numberofregions(i)) = leftregiony(i, selectedregion);
            leftregionz(i, numberofregions(i)) = leftregionz(i, selectedregion);
            rightregionx(i, numberofregions(i)) = rightregionx(i, selectedregion);
            rightregiony(i, numberofregions(i)) = rightregiony(i, selectedregion);
            rightregionz(i, numberofregions(i)) = rightregionz(i, selectedregion);
            regionimportant(i, numberofregions(i)) = regionimportant(i, selectedregion);
            leftregionradius(i, numberofregions(i)) = leftregionradius(i, selectedregion);
            rightregionradius(i, numberofregions(i)) = rightregionradius(i, selectedregion);
            regionname(i, numberofregions(i),:) = newnamestring;
        end
        if frame>=ifrom && frame<=ito
            selectedregion = numberofregions(i);
        end
        canselectregion = true;
        canadjustregion = true;
        canadjustmeasurement = true;
        canshowneurons = true;
        cancalculate = true;
        set(handles.showneurons,'Value',1);
        updateselection;
        updatevisibility;
        showframe(hobj, eventdata);
    end

    function switchapplypreset (hobj, eventdata) %#ok<INUSD>
        if strcmp(get(handles.applypreset, 'Enable'), 'on') == 1
            if (get(handles.applypreset, 'Value') == 6) %If manual
                set(controlapplymanual, 'Enable', 'on');
            else
                set(controlapplymanual, 'Enable', 'off');
            end
        else
            set(controlapplymanual, 'Enable', 'off');
        end
        preserveapply;
    end

    function switchforeground(hobj, eventdata) %#ok<INUSD>
        if (strcmp(get(handles.foregroundpopup, 'Enable'), 'on') == 1)
            if (get(handles.foregroundpopup, 'Value') == 1 || get(handles.foregroundpopup, 'Value') == 2) % Fixed number of or fixed proportion of pixels
                set(handles.pixelnumbertext, 'Enable', 'on', 'Visible', 'on');
                set(handles.pixelnumber, 'Enable', 'on', 'Visible', 'on');
                setpixelnumber; %making sure that it is a round number if it's switched to fixed number
            else %All pixels
                set(handles.pixelnumbertext, 'Enable', 'off', 'Visible', 'off');
                set(handles.pixelnumber, 'Enable', 'off', 'Visible', 'off');
            end
        else
            if (get(handles.foregroundpopup, 'Value') == 1 || get(handles.foregroundpopup, 'Value') == 2) % Fixed number of or fixed proportion of pixels
                set(handles.pixelnumbertext, 'Enable', 'off', 'Visible', 'on');
                set(handles.pixelnumber, 'Enable', 'off', 'Visible', 'on');
            else
                set(handles.pixelnumbertext, 'Enable', 'off', 'Visible', 'off');
                set(handles.pixelnumber, 'Enable', 'off', 'Visible', 'off');
            end
        end

    end

    function switchbackground(hobj, eventdata) %#ok<INUSD>
        if strcmp(get(handles.backgroundpopup, 'Enable'), 'on')
            if get(handles.backgroundpopup, 'Value') == 1 %Percentile
                set(handles.percentiletext, 'Enable', 'on', 'Visible', 'on');
                set(handles.percentile, 'Enable', 'on', 'Visible', 'on');
                set(handles.offsettext, 'Enable', 'off', 'Visible', 'off');
                set(handles.offset, 'Enable', 'off', 'Visible', 'off');
                set(handles.localbackground, 'Visible', 'on', 'Enable', 'on');
            elseif get(handles.backgroundpopup, 'Value') == 3 %Camera offset
                set(handles.percentiletext, 'Enable', 'off', 'Visible', 'off');
                set(handles.percentile, 'Enable', 'off', 'Visible', 'off');
                set(handles.offsettext, 'Enable', 'on', 'Visible', 'on');
                set(handles.offset, 'Enable', 'on', 'Visible', 'on');
                set(handles.localbackground, 'Visible', 'off', 'Enable', 'off', 'Value', 0);
            else %Median or no background subtraction
                set(handles.percentiletext, 'Enable', 'off', 'Visible', 'off');
                set(handles.percentile, 'Enable', 'off', 'Visible', 'off');
                set(handles.offsettext, 'Enable', 'off', 'Visible', 'off');
                set(handles.offset, 'Enable', 'off', 'Visible', 'off');
                set(handles.localbackground, 'Visible', 'off', 'Enable', 'off', 'Value', 0);
            end
        else
            if get(handles.backgroundpopup, 'Value') == 1 %Percentile
                set(handles.percentiletext, 'Enable', 'off', 'Visible', 'on');
                set(handles.percentile, 'Enable', 'off', 'Visible', 'on');
                set(handles.offsettext, 'Enable', 'off', 'Visible', 'off');
                set(handles.offset, 'Enable', 'off', 'Visible', 'off');
                set(handles.localbackground, 'Visible', 'on', 'Enable', 'off');
            elseif get(handles.backgroundpopup, 'Value') == 3 %Camera offset
                set(handles.percentiletext, 'Enable', 'off', 'Visible', 'off');
                set(handles.percentile, 'Enable', 'off', 'Visible', 'off');
                set(handles.offsettext, 'Enable', 'off', 'Visible', 'on');
                set(handles.offset, 'Enable', 'off', 'Visible', 'on');
                set(handles.localbackground, 'Visible', 'off', 'Enable', 'off', 'Value', 0);
            else
                set(handles.percentiletext, 'Enable', 'off', 'Visible', 'off');
                set(handles.percentile, 'Enable', 'off', 'Visible', 'off');
                set(handles.offsettext, 'Enable', 'off', 'Visible', 'off');
                set(handles.offset, 'Enable', 'off', 'Visible', 'off');
                set(handles.localbackground, 'Visible', 'off', 'Enable', 'off', 'Value', 0);
            end
        end
        if ~(get(handles.backgroundpopup, 'Value') == 1 && get(handles.localbackground, 'Value') == 1)
            delete(findobj(handles.img, 'type', 'line', 'color', 'k'));
        end
    end

    function saturationcheck(hobj, eventdata)%#ok<INUSD>
        set(controlcrop, 'Enable', 'off');
        set(controlsetalignment, 'Enable', 'off');
        set(controldetect, 'Enable', 'off');
        set(controlcalculate, 'Enable', 'off');
        set(handles.load, 'Enable', 'off');
        
        figure; hold on;
        title('Absolute intensity values of the brightest pixels in the two channels', 'Interpreter', 'none');
        xlabel('frame');
        ylabel('intensity');
        h=gca;
        legenddisplayed = false;
        
        maxl = -Inf;
        maxr = -Inf;
        
        for i=1:nf
            cachesubimages(i);
            L = LEFT(i);
            R = RIGHT(i);
            if i > 1
                maxlprev = maxlnow;
                maxrprev = maxrnow;
            end
            maxlnow = max(L(:));
            maxrnow = max(R(:));
            if maxlnow > maxl
                maxl = maxlnow;
            end
            if maxrnow > maxr
                maxr = maxrnow;
            end
            if i > 1
                if get(handles.channelchooser, 'Value') == 1
                    plot(h,[i-1 i], [maxlprev maxlnow], '-y');
                    plot(h,[i-1 i], [maxrprev maxrnow], '-c');
                elseif get(handles.channelchooser, 'Value') == 2
                    plot(h,[i-1 i], [maxrprev maxrnow], '-y');
                    plot(h,[i-1 i], [maxlprev maxlnow], '-c');
                end
            else
                if get(handles.channelchooser, 'Value') == 1
                    plot(h,i, maxlnow, '-y');
                    plot(h,i, maxrnow, '-c');
                elseif get(handles.channelchooser, 'Value') == 2
                    plot(h,i, maxrnow, '-y');
                    plot(h,i, maxlnow, '-c');
                end
            end
            if mod(i,25) == 1
                drawnow;
                if (~legenddisplayed)
                    legend(['YFP';'CFP']);
                    legenddisplayed = true;
                end
            end
        end
        
        hold off;
        
        fprintf('The brightest pixel in the left channel has an intensity of %d ; the brightest one in the right channel has %d .\n', maxl, maxr);
        
        updatevisibility;
    end

    function mediancheck(hobj, eventdata) %#ok<INUSD>
        set(controlcrop, 'Enable', 'off');
        set(controlsetalignment, 'Enable', 'off');
        set(controldetect, 'Enable', 'off');
        set(handles.load, 'Enable', 'off');
        set(controlcalculate, 'Enable', 'off');
        
        bgindex = 0;
        stepsize=100; %median approximated based on at least 10, at most 50 frames, with a preferred number of nf/100 frames
        if nf/stepsize < 10
            stepsize = floor(nf/10);
        end
        if nf/stepsize > 50
            stepsize = ceil(nf/50);
        end
        if stepsize < 1
            stepsize = 1;
        end
        lnow = NaN(subchannelsizey, subchannelsizex, floor(nf/stepsize));
        rnow = NaN(subchannelsizey, subchannelsizex, floor(nf/stepsize));
        waithandle = waitbar(0,'Median pixel check...','Name','Processing', 'CreateCancelBtn', 'delete(gcbf)');
        for i=1:stepsize:nf
            if ishandle(waithandle) > 0
                if mod(i, waitbarfps) == 0
                    waitbar(i/nf, waithandle);
                end
            else
                break;
            end
            cachesubimages(i);
            bgindex = bgindex + 1;
            lnow(:,:,bgindex) = LEFT(i);
            rnow(:,:,bgindex) = RIGHT(i);
        end

        if ishandle(waithandle) > 0 %Only display results if calculation was not cancelled
            close(waithandle);
            lmedian = median(lnow,3);
            rmedian = median(rnow,3);
            if get(handles.channelchooser, 'Value') == 1
                ratiomedian = lmedian./rmedian;
            elseif get(handles.channelchooser, 'Value') == 2
                ratiomedian = rmedian./lmedian;
            end

            figure;
            imshow(lmedian,[], 'InitialMagnification', 100); colormap(jet); colorbar;
            title(['Median pixel intensity in the LEFT channel for ' file], 'Interpreter', 'none');
            xlabel('x location');
            ylabel('y location');

            figure;
            imshow(rmedian,[], 'InitialMagnification', 100); colormap(jet); colorbar;
            title(['Median pixel intensity in the RIGHT channel for ' file], 'Interpreter', 'none');
            xlabel('x location');
            ylabel('y location');

            figure;
            imshow(ratiomedian,[], 'InitialMagnification', 100); colormap(jet); colorbar;
            title(['Median pixel intensity RATIO for ' file], 'Interpreter', 'none');
            xlabel('x location');
            ylabel('y location');
            fprintf('The largest median ratio difference is %.2f . The standard deviation of the median ratio across pixels is %.3f .\n', max(ratiomedian(:))-min(ratiomedian(:)), std(ratiomedian(:)));
        end

        updatevisibility;
    end

    function [fromvalue, tovalue, allregions] = fromto
        fromvalue = round(str2double(get(handles.applyfrom, 'String')));
        tovalue = round(str2double(get(handles.applyto, 'String')));
        if get(handles.applypreset, 'Value') == 5 %The index of the 'every region in every frame' setting in the drop-down menu
            allregions = true;
        else
            allregions = false;
        end
    end

    function updatesubchannelsizes
        if get(handles.channelchooser, 'Value') ~= 3 && ~stacktucam
            subchannelsizex = max(min(leftwidth-cropleft-unusablerightx-cropright, originalsizex-rightdisplacementx+1-cropleft-unusablerightx-cropright),0);
            subchannelsizey = max(originalsizey - croptop - cropbottom - abs(rightdisplacementy),0);
        else
            if stacktucam
                subchannelsizex = max(originalsizex/2-cropleft-cropright, 0);
                subchannelsizey = max(originalsizey-croptop-cropbottom, 0);
            else
                subchannelsizex = max(originalsizex-cropleft-cropright, 0);
                subchannelsizey = max(originalsizey-croptop-cropbottom, 0);
            end
        end
        set(handles.subchannelsizedisplay, 'String', [num2str(subchannelsizex) 'x' num2str(subchannelsizey)]);
        %as subchannel size is changed, we cannot use cached image with previous subchannel size
        leftcached = 0;
        rightcached = 0;
        updategoodchannelsize;
    end

    function clearselection (hobj, eventdata) %#ok<INUSD>
        selectedregion = 0;
        selectedradiusy = 0;
        selectedradiusc = 0;
        selectedname = char(ones(1,5)*45);
        
        set(handles.regionnamedisplay,'String',selectedname);
        set(handles.regionnametext,'String','Region name (0)');
        set(handles.measureregion,'Value', 0);
        set(handles.adjustleft,'String','Left (0;0)');
        set(handles.adjustright,'String','Right (0;0)');
        set(handles.leftradiusdisplay,'String', num2str(selectedradiusy));
        set(handles.rightradiusdisplay,'String', num2str(selectedradiusc));

        canadjustregion = false;
        set(controladjustregion, 'Enable', 'off'); %cannot call updatevisibility as that would enable buttons that should not be enabled during calculation
        if ~isnan(subchannelsizex) && subchannelsizex > 0 && ~isnan(subchannelsizey) && subchannelsizey > 0 && ~isnan(rightdisplacementx) && ~isnan(rightdisplacementy) && cansetalignment && ~dontupdatevisibility %if channel size is reasonable, and can set alignment (e.g. it's not after an unload command), enable adding of regions
            set(handles.addregion, 'Enable', 'on');
            set(handles.addarb, 'Enable', 'on');
            set(handles.applypreset, 'Enable', 'on');
            set(handles.applypresettext, 'Enable', 'on');
            switchapplypreset;
        end
        
        if max(numberofregions(:)) <= 0
            clearallregions;
            updatevisibility;
        end

        currentlyselected = false;
    end

    function clearallregions (hobj,eventdata) %#ok<INUSD>
        %Clearing data that would no longer be appropriate, for example,
        %with a differently set up alignment
        maxnumberofregions = 0;
        numberofregions = []; %just to clear it; will be set to appropriate sized array of zeros when a file is loaded
        if (nf ~= 0 && ~isnan(nf))
            numberofregions = zeros(nf,1);
        end
        leftregionx = [];
        leftregiony = [];
        rightregionx = [];
        rightregiony = [];
        regionimportant = [];
        regionname = [];
        leftregionradius = [];
        rightregionradius = [];
        selectedregion = 0;
        selectedname = char(ones(1,5)*45); % '-----', meaning that name is unavailable as no neuron is selected
        selectedradiusy = 0;
        selectedradiusc = 0;
        canadjustregion = false;
        canselectregion = false;
        cancalculate = false;
        canadjustmeasurement = false;
        canshowneurons = false;
        updatevisibility;
    end

    function disableeverythingtemp(hobj, eventdata) %#ok<INUSD>
        set(controlshowneurons, 'Enable', 'off');
        set(controlselectregion, 'Enable', 'off');
        set(controladjustregion, 'Enable', 'off');
        set(controlsetfile, 'Enable', 'off');
        set(controlbrowsemovie, 'Enable', 'off')
        set(controlsetchannel, 'Enable', 'off');
        set(controlapplymanual, 'Enable', 'off');
        set(controlmanipulate, 'Enable', 'off');
        set(controlcrop, 'Enable', 'off');
        set(controlsetalignment, 'Enable', 'off');
        set(controldetect,'Enable','off');
        set(controlcalculate, 'Enable', 'off');
        set(controladjustmeasurement, 'Enable', 'off');
        set(controlplot, 'Enable', 'off');
        set(handles.load, 'Enable', 'off');
        set(handles.readspeed, 'Enable', 'off');
        switchbackground;
        switchforeground;
    end

    function updatevisibility(hobj, eventdata) %#ok<INUSD>
        if ~dontupdatevisibility %TODO: this was a quick fix that should be handled more properly
            if any(arbarea(:))
                set(handles.showarb, 'Visible', 'on');
            else
                set(handles.showarb, 'Visible', 'off');
            end
            set(handles.load, 'Enable', 'on');
            if cansetfile
                set(controlsetfile, 'Enable', 'on');
            else
                set(controlsetfile, 'Enable', 'off');
            end
            if canbrowsemovie
                set(controlbrowsemovie,'Enable','on');
            else
                set(controlbrowsemovie,'Enable','off');
            end
            if cancalculate
                set(controlcalculate,'Enable','on');
            else
                set(controlcalculate,'Enable','off');
            end
            if cansetalignment
                set(controlsetalignment, 'Enable', 'on');
            else
                set(controlsetalignment, 'Enable', 'off');
            end
            if candetect
                set(controldetect,'Enable','on');
            else
                set(controldetect,'Enable','off');
            end
            if canselectregion
                set(controlselectregion,'Enable','on');
            else
                set(controlselectregion,'Enable','off');
            end
            if canadjustregion
                set(controladjustregion,'Enable', 'on');
            else
                set(controladjustregion,'Enable', 'off');
            end
            if canmanipulate
                set(controlmanipulate,'Enable', 'on');
            else
                set(controlmanipulate,'Enable', 'off');
            end
            if canadjustmeasurement
                set(controladjustmeasurement, 'Enable', 'on');
            else
                set(controladjustmeasurement, 'Enable', 'off');
            end
            if cancrop
                set(controlcrop, 'Enable', 'on');
            else
                set(controlcrop, 'Enable', 'off');
            end
            if canplot
                set(controlplot, 'Enable', 'on');
            else
                set(controlplot, 'Enable', 'off');
            end
%            if canmanipulate %switchapplypreset should take care of it
%                set(controlmanipulate, 'Enable', 'on');
%            else
%                set(controlmanipulate, 'Enable', 'off');
%            end
            if cansetchannel
                set(controlsetchannel, 'Enable', 'on');
            else
                set(controlsetchannel, 'Enable', 'off');
            end
            if canshowneurons
                set(controlshowneurons, 'Enable', 'on');
            else
                set(controlshowneurons, 'Enable', 'off', 'Value', 0);
            end
            if speedreadable
                set(handles.readspeed, 'Enable', 'on');
            else
                set(handles.readspeed, 'Enable', 'off');
            end
            switchforeground;
            switchbackground;
			switchapplypreset;
            updategoodchannelsize;
        end
    end

    function updategoodchannelsize
        if ~dontupdatevisibility %TODO: this was a quick fix that should be handled more properly
            if ~isnan(subchannelsizex) && subchannelsizex > 0 && ~isnan(subchannelsizey) && subchannelsizey > 0 && ~isnan(rightdisplacementx) && ~isnan(rightdisplacementy) && cansetalignment %if channel size is reasonable, and can set alignment (e.g. it's not after an unload command), enable adding of regions
                candetect = true;
                cansetchannel = true;
                set(controldetect, 'Enable', 'on');
                set(controlsetchannel, 'Enable', 'on');
                set(handles.addregion, 'Enable', 'on');
                set(handles.addarb, 'Enable', 'on');
                set(handles.applypreset, 'Enable', 'on');
                set(handles.applypresettext, 'Enable', 'on');
            else
                candetect = false;
                cansetchannel = false;
                set(controldetect, 'Enable', 'off');
                set(controlsetchannel, 'Enable', 'off');
                set(handles.addregion, 'Enable', 'off');
                set(handles.addarb, 'Enable', 'off');
                set(handles.applypreset, 'Enable', 'off');
                set(handles.applypresettext, 'Enable', 'off');
            end
            switchapplypreset;
        end
    end

    function enableeverything(hobj, eventdata) %#ok<INUSD>
        
        canplot = true;
        canmanipulate = true;
        cancrop = true;
        cansetfile = true;
        canbrowsemovie = true;
        cansetchannel = true;
        canshowneurons = true;
        cancalculate = true;
        cansetalignment = true;
        candetect = true;
        canselectregion = true;
        canadjustregion = true;
        canadjustmeasurement = true;
        
        currentlycalculating = false;
        
        dontupdatevisibility = false;
        
        updatevisibility;
        
        set(handles.readspeed, 'Enable', 'on');
        
    end

    function checkz(hobj, eventdata) %#ok<INUSD>
        
        set(controlzstack, 'Visible', 'on');
        maxproject = get(handles.maxproject, 'Value');
        
        if maxproject
            set(controlz, 'visible', 'off');
            set(handles.minusfifty, 'Position',[0.00 0 0.04 0.05]);
            set(handles.frame, 'Position',[0.04 0 0.81 0.05]);
            showframe;
        else
            set(controlz, 'visible', 'on');
            set(handles.minusfifty, 'Position',[0.20 0 0.04 0.05]);
            set(handles.frame, 'Position',[0.24 0 0.61 0.05]);
            set(handles.zpos, 'min', 1, 'max', numel(uniqueposz), 'SliderStep', [1/(numel(uniqueposz)-1) 10/(numel(uniqueposz)-1)]);
            setz();
        end
        
    end

    function equalizeradii (hobj, eventdata)
        for i=1:nf
            for j=1:numberofregions(i)
                if rightregionradius(i,j) >= leftregionradius(i,j)
                    leftregionradius(i,j) = rightregionradius(i,j);
                else
                    rightregionradius(i,j) = leftregionradius(i,j);
                end
            end
        end
        showframe(hobj, eventdata);
    end

    function measureonlythis (hobj, eventdata) %#ok<INUSD>
        for i=1:nf
            for j=1:numberofregions(i)
                if (strcmp(char(regionname(i, j, :)), selectedname) ~= 1)
                    regionimportant(i, j) = 0;
%                else
%                    regionimportant(i, j) = 1;
                end
            end
            for j=1:numberofregionsfound %clear nonselected region results
                if (strcmp(selectedname, char(rationames(j,:))) ~= 1)
                    leftvalues(i,j) = NaN;
                    rightvalues(i,j) = NaN;
                    leftbackground(i,j) = NaN;
                    rightbackground(i,j) = NaN;
                    ratios(i,j) = NaN;
                end
            end
        end
        
        for j=numberofregionsfound:-1:1
            removeifempty(j);
        end
        
    end

    function saveanalysis (hobj, eventdata) %#ok<INUSD>
        %Saving everything in one struct
        
        saveit = true;
        
        checkanalysisoldstyle = [file(1:end-4) '-analysisdata.mat'];
        dots = strfind(file, '.');
        if ~isempty(dots)
            checkanalysisnewstyle = [file(1:dots(end)-1) '-analysisdata.mat'];
        else
            checkanalysisnewstyle = checkanalysisoldstyle;
        end
        
        %checkanalysisnewstyle = fullfile(currentpath, checkanalysisnewstyle);
        %checkanalysisoldstyle = fullfile(currentpath, checkanalysisoldstyle);
        
        %Don't save it if the user doesn't want to overwrite the already existing saved data
        if exist(checkanalysisnewstyle, 'file') ~= 0 || exist(checkanalysisoldstyle, 'file') ~= 0
           if ~strcmp(questdlg('Analysis data already exists for this file. Overwrite it?','Data already exists','Cancel','Overwrite','Overwrite'),'Overwrite')
               saveit = false;
           end
        end
        
        if saveit
        
            analysisdata = struct;

            for i=1:size(trytoload, 2)
                eval(['analysisdata.' char(trytoload(i)) '=' char(trytoload(i)) ';']);
            end

            for i=1:size(trytosetstring, 2)
                eval(['analysisdata.' char(trytosetstring(i)) '= str2double(get(handles.' char(trytosetstring(i)) ',''String''));']);
            end

            for i=1:size(trytosetvalue, 2)
                eval(['analysisdata.' char(trytosetvalue(i)) '= get(handles.' char(trytosetvalue(i)) ',''Value'');']);
            end
            
            analysisdata.version = version; %#ok<STRNU>

            save(checkanalysisnewstyle, '-struct', 'analysisdata');

            fprintf('Analysis saved as %s .\n', checkanalysisnewstyle);

            questdlg('Analysis data saved successfully.', 'Analysis saved', 'OK', 'OK');
            
            if exist(checkanalysisoldstyle, 'file') ~= 0 && ~strcmpi(checkanalysisoldstyle, checkanalysisnewstyle)
                if strcmp(questdlg(sprintf('Apart from the analysis file just saved as %s , there is an additional analysis data file named %s . It is probably an outdated save file from an earlier version of the analyser. Shall we remove it?', checkanalysisnewstyle, checkanalysisoldstyle),'Multiple savefiles exist for the same movie', 'Keep both', 'Delete older', 'Delete older'), 'Delete older')
                    delete(checkanalysisoldstyle);
                    fprintf('Outdated analysis save file %s has been successfully deleted.\n', checkanalysisoldstyle);
                end
            end
            
        end
        
    end

    function loadanalysis (hobj, eventdata)
        %Loading everything in one struct
        
        checkanalysisoldstyle = [file(1:end-4) '-analysisdata.mat'];
        dots = strfind(file, '.');
        if ~isempty(dots)
            checkanalysisnewstyle = [file(1:dots(end)-1) '-analysisdata.mat'];
        else
            checkanalysisnewstyle = checkanalysisoldstyle;
        end
        checkanalysisneweststyle = fullfile(currentpath, checkanalysisnewstyle);
        
        if exist(checkanalysisneweststyle, 'file') ~= 0
            neweststyleexists = true;
        else
            neweststyleexists = false;
        end
        if exist(checkanalysisnewstyle, 'file') ~= 0
            newstyleexists = true;
        else
            newstyleexists = false;
        end
        if exist(checkanalysisoldstyle, 'file') ~= 0
            oldstyleexists = true;
        else
            oldstyleexists = false;
        end
        
        
        if ~neweststyleexists && ~newstyleexists && ~oldstyleexists
            questdlg('No analysis data found', 'Loading analysis data', 'OK', 'OK');
        else
            if neweststyleexists
                analysisdata = load(checkanalysisneweststyle);
            elseif newstyleexists && ~oldstyleexists %only new
                analysisdata = load(checkanalysisnewstyle);
            elseif oldstyleexists && ~newstyleexists %only old
                analysisdata = load(checkanalysisoldstyle);
                if strcmp(questdlg('The analysis data for this file is in the old name format. Shall we rename it according to the new convention?','Rename old-style analysis file', 'Rename it', 'Keep it as it is', 'Rename it'), 'Rename it')
                    movefile(checkanalysisoldstyle, checkanalysisnewstyle);
                end
            elseif newstyleexists && oldstyleexists %both new and old
                if strcmpi(checkanalysisoldstyle, checkanalysisnewstyle) %but they're the same
                    analysisdata = load(checkanalysisnewstyle);
                else %they're different, so we need to choose
                    if strcmp(questdlg('Two different analysis save files are available for this movie. Which one shall we load?','Multiple savefiles exist for the same movie', checkanalysisnewstyle, checkanalysisoldstyle, checkanalysisnewstyle), checkanalysisnewstyle)
                        analysisdata = load(checkanalysisnewstyle);
                    else
                        analysisdata = load(checkanalysisoldstyle);
                    end
                end
            else
                printf(2, 'Warning: did not know what analysisdata to read.\n');
            end

            firstunloadable = true;
            %for compatibility with older save files            
            for i=1:size(trytoload, 2)
                if isfield(analysisdata, trytoload(i))
                    eval([char(trytoload(i)) '= analysisdata.' char(trytoload(i)) ';']);
                else
                    if firstunloadable
                        fprintf('Data to be loaded does not contain values for the fields: ''%s''', char(trytoload(i)));
                        firstunloadable = false;
                    else
                        fprintf(', ''%s''', char(trytoload(i)));
                    end
                end
            end
            
            %converting old-style threshold vectors (of always the same value) to single numbers
            if numel(rightthreshold) > 1
                rightthreshold = rightthreshold(1);
            end
            if numel(leftthreshold) > 1
                leftthreshold = leftthreshold(1);
            end
            
            for i=1:size(trytosetstring, 2)
                if isfield(analysisdata, trytosetstring(i))
                    eval(['set(handles.' char(trytosetstring(i)) ',''String'', analysisdata.' char(trytosetstring(i)) ');']);
                else
                    if firstunloadable
                        fprintf('Data to be loaded does not contain values for the fields: ''%s''', char(trytosetstring(i)));
                        firstunloadable = false;
                    else
                        fprintf(', ''%s''', char(trytosetstring(i)));
                    end
                end
            end
            
            for i=1:size(trytosetvalue, 2)
                if isfield(analysisdata, trytosetvalue(i))
                    eval(['set(handles.' char(trytosetvalue(i)) ',''Value'', analysisdata.' char(trytosetvalue(i)) ');']);
                else
                    converted = false;
                    if strcmp(trytosetvalue(i), 'channelchooser') && isfield(analysisdata, 'yfpleft') && isfield(analysisdata, 'cfpleft')
                        if analysisdata.yfpleft
                            set(handles.channelchooser, 'Value', 1);
                            converted = true;
                        elseif analysisdata.cfpleft
                            set(handles.channelchooser, 'Value', 2);
                            converted = true;
                        end
                    end
                    if ~converted
                        if firstunloadable
                            fprintf('Data to be loaded does not contain values for the fields: ''%s''', char(trytosetvalue(i)));
                            firstunloadable = false;
                        else
                            fprintf(', ''%s''', char(trytosetvalue(i)));
                        end
                    end
                end
            end
            
            %converting old-style bleedthrough correction to new style
            if (~isfield(analysisdata, 'correctionfactorA') || ~isfield(analysisdata, 'correctionfactorB')) && (any(any(~isnan(ratios))) || any(any(~isnan(leftvalues))) || any(any(~isnan(rightvalues))))
                if isfield(analysisdata, 'correctionfactor')
                    oldcorrectionfactor = analysisdata.correctionfactor;
                else
                    oldcorrectionfactor = 0.60;
                end
                correctionresponse = questdlg(sprintf('The savefile contains ratio data that was apparently bleedthrough-corrected using the simple subtraction method, with a factor of %.3f. Re-adjust and correct it using the new method (A=%.3f ; B=%.3f)?', oldcorrectionfactor, correctionfactorA, correctionfactorB),'Old-style correction factor found in saved data','Correct the results','Clear the results','Keep the results','Correct the results');
                if strcmp(correctionresponse,'Correct the results')
                    %correcting ratios 
                    if get(handles.channelchooser, 'Value') == 1 %YFP left
                        leftvalues = leftvalues + rightvalues*oldcorrectionfactor;
                    elseif get(handles.channelchooser, 'Value') == 2 %YFP right
                        rightvalues = rightvalues + leftvalues*oldcorrectionfactor;
                    end
                    ratios = (ratios + oldcorrectionfactor - correctionfactorA) * correctionfactorB;
                elseif strcmp(correctionresponse,'Clear the results')
                    %clearing ratios
                    leftvalues(:,:) = NaN;
                    rightvalues(:,:) = NaN;
                    leftbackground(:,:) = NaN;
                    rightbackground(:,:) = NaN;
                    ratios(:,:) = NaN;
                    canplot = false;
                elseif strcmp(correctionresponse,'Keep the results')
                    correctionfactorA = oldcorrectionfactor;
                    correctionfactorB = 1;
                    set(handles.correctionfactorA, 'String', num2str(correctionfactorA));
                    set(handles.correctionfactorB, 'String', num2str(correctionfactorB));
                end
            end
            
            if ~firstunloadable
                errormessage = 'Some expected variables were missing from the analysis save file';
                if (isfield(analysisdata, 'version') && strcmp(analysisdata.version, version) ~= 1)
                    errormessage = [errormessage ', probably because it was saved with version ' analysisdata.version ', whereas this analysis program is version ' version '. '];
                    fprintf('. The save file appears to be version %s. This analysis program is version %s. ', analysisdata.version, version);
                else
                    fprintf('. Perhaps it was saved with an early version of this program. ');
                    errormessage = [errormessage ', probably because it was saved with an earlier version of this program.'];
                end
                
                questdlg([errormessage 'To avoid losing any data, all known variables found in the save file have been loaded. As this bypasses the normal order of initialization, the operation may have left some variables set to zero or NaN. If in doubt, reanalyse.'], 'Problems with loading data', 'OK', 'OK');
            end
            
            clearselection(hobj, eventdata);
            updatesubchannelsizes;

            if ~isnan(rightdisplacementy)
                cancrop = true;
                candetect = true;
%                cansetchannel = true;
            end
            if maxnumberofregions >= 1
                canshowneurons = true;
                cancalculate = true;
                canselectregion = true;
                canadjustmeasurement = true;
            end
            if sum(sum(~isnan(ratios))) > 0
                canplot = true;
                canmanipulate = true;
            end
            if currentlyselected
                canadjustregion = true;
            end
            updatevisibility;

            set(handles.alignmentx, 'String', num2str(rightdisplacementx));
            set(handles.alignmenty, 'String', num2str(rightdisplacementy));
            set(handles.croplmiddle, 'String', num2str(leftwidth));
            set(handles.croprmiddle, 'String', num2str(rightdisplacementx+unusablerightx));
            set(handles.cropleft, 'String', num2str(cropleft));
            set(handles.cropright, 'String', num2str(cropright));
            set(handles.croptop, 'String', num2str(croptop));
            set(handles.cropbottom, 'String', num2str(cropbottom));
            
            if gaussianx ~= 0
                set(handles.filter, 'String', ['[' num2str(gaussianx) ' ' num2str(gaussiany) '], ' num2str(gaussians)]);
            else
                set(handles.filter, 'String', num2str(gaussianx));
            end
            if exist('leftregionz', 'var') ~= 1 || exist('rightregionz', 'var') ~= 1 || numel(leftregionz) ~= numel(leftregionx) || numel(rightregionz) ~= numel(rightregionx)
                leftregionz = ones(size(leftregionx));
                rightregionz = ones(size(rightregionx));
            end
            
            setfilter;

            showframe(hobj, eventdata);

            if firstunloadable
                fprintf('Analysis data loaded successfully.\n');
            else
                fprintf('Analysis data loaded.\n');
            end
        end
    end

    function exportdataaslog (hobj, eventdata) %#ok<INUSD>
        if (isempty(selectedregion) || selectedregion == 0) && ~get(handles.showarb, 'Value')
            questdlg('You must first select a region to export.', 'Error during data export', 'OK', 'OK');
            return
        end
        if (numberofregionsfound >= 1)
            waithandle = waitbar(0,'Exporting data as a log file...','Name','Processing', 'CreateCancelBtn', 'delete(gcbf)');
            dots = strfind(file, '.');
            if isempty(dots)
                lastvalidchar = numel(file); %if we didn't find any dots in the full filename, then we'll just use the whole filename
            else
                lastvalidchar = dots(end)-1;
            end
            if get(handles.showarb, 'Value')
                exportname = 'arb  ';
            else
                exportname = squeeze(selectedname)';
            end
            exportfilename = fullfile(currentpath, sprintf('%s-%s-%s', file(1:lastvalidchar), strtrim(exportname), 'exported.log'));
            exportfile = fopen(exportfilename, 'w');
            
            for i=1:nf
                if get(handles.showarb, 'Value')
                    for j=1:size(rationames, 1)
                        if strcmpi(char(rationames(j, :)), 'arb  ')
                            fprintf(exportfile, '%d ', i); %frame
                            fprintf(exportfile, '%.0f ', leftbackground(i, j)); %left background
                            fprintf(exportfile, '%.0f ', rightbackground(i, j)); %right background
                            fprintf(exportfile, '%.2f ', 0); %left x
                            fprintf(exportfile, '%.2f ', 0); %left y
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, '%.0f ', sum(arbarea(:))); %left area
                            fprintf(exportfile, '%.0f ', leftvalues(i, j)); %left value
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, '%.2f ', 0); %right x
                            fprintf(exportfile, '%.2f ', 0); %right y
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, '%.0f ', sum(arbarea(:))); %right area
                            fprintf(exportfile, '%.0f ', rightvalues(i, j)); %left value
                            fprintf(exportfile, '\n');
                            break;
                        end
                    end
                else
                    for j=1:numberofregions(i)
                        if (strcmp(char(regionname(i, j, :)), char(rationames(selectedregion, :))) == 1)
                            fprintf(exportfile, '%d ', i); %frame
                            fprintf(exportfile, '%.0f ', leftbackground(i, j)); %left background
                            fprintf(exportfile, '%.0f ', rightbackground(i, j)); %right background
                            fprintf(exportfile, '%.2f ', leftregionx(i, selectedregion)); %left x
                            fprintf(exportfile, '%.2f ', leftregiony(i, selectedregion)); %left y
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, '%.0f ', leftregionradius(i, selectedregion).^2 * pi()); %left area
                            fprintf(exportfile, '%.0f ', leftvalues(i, j)); %left value
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, '%.2f ', rightregionx(i, selectedregion)); %right x
                            fprintf(exportfile, '%.2f ', rightregiony(i, selectedregion)); %right y
                            fprintf(exportfile, ' ');
                            fprintf(exportfile, '%.0f ', rightregionradius(i, selectedregion).^2 * pi()); %right area
                            fprintf(exportfile, '%.0f ', rightvalues(i, j)); %left value
                            fprintf(exportfile, '\n');
                            break;
                        end
                    end
                end
            end

            fclose(exportfile);
        end
        if exist('waithandle', 'var') == 1 && ishandle(waithandle)
            close(waithandle);
            fprintf('Exported results as a log file.\n');
        end
    end

    function exportdataastxt (hobj, eventdata) %#ok<INUSD>
        if (numberofregionsfound >= 1)
            waithandle = waitbar(0,'Exporting data as plaintext...','Name','Processing', 'CreateCancelBtn', 'delete(gcbf)');
            dots = strfind(file, '.');
            if isempty(dots)
                lastvalidchar = numel(file); %if we didn't find any dots in the full filename, then we'll just use the whole filename
            else
                lastvalidchar = dots(end)-1;
            end
            
            exportfilename = fullfile(currentpath, sprintf('%s-%s', file(1:lastvalidchar), 'exported.txt'));
            exportfile = fopen(exportfilename, 'w');
            
            fprintf(exportfile, 'Frame');
            for j=1:numberofregionsfound
                fprintf(exportfile, '\t%s ratios', strtrim(char(rationames(j, :))));
            end
            fprintf(exportfile, '\n');
            for i=1:nf
                fprintf(exportfile,'%d', i); %frame
                for j=1:numberofregionsfound
                    fprintf(exportfile, '\t%f', ratios(i, j));
                end
                fprintf(exportfile, '\n');
            end
                %{
                exportfile = fopen([file(1:end-4) '-' strtrim(char(rationames(k, :))) '-output.txt'], 'w');
                fprintf(exportfile, 'frame number\t');
                for m=1:18
                    if m==12 && ~usingbehaviour %don't 
                        break;
                    end
                    fprintf(exportfile, strtrim(char(rationames(k, :))));
                    switch m
                        case 1
                            fprintf(exportfile, ' ratio\t');
                        case 2
                            fprintf(exportfile, ' left signal\t');
                        case 3
                            fprintf(exportfile, ' right signal\t');
                        case 4
                            fprintf(exportfile, ' left background\t');
                        case 5
                            fprintf(exportfile, ' right background\t');
                        case 6
                            fprintf(exportfile, ' left x-coordinate\t');
                        case 7
                            fprintf(exportfile, ' right x-coordinate\t');
                        case 8
                            fprintf(exportfile, ' left y-coordinate\t');
                        case 9
                            fprintf(exportfile, ' right y-coordinate\t');
                        case 10
                            fprintf(exportfile, ' left radius\t');
                        case 11
                            fprintf(exportfile, ' right radius\t');
                        case 12
                            fprintf(exportfile, ' unknown behaviour\t');
                        case 13
                            fprintf(exportfile, ' stationary\t');
                        case 14
                            fprintf(exportfile, ' forwards movement\t');
                        case 15
                            fprintf(exportfile, ' backwards movement\t');
                        case 16
                            fprintf(exportfile, ' 1\t');
                        case 17
                            fprintf(exportfile, ' 2\t');
                        case 18
                            fprintf(exportfile, ' 3\t');
                    end
                end
                fprintf(exportfile, '\n');

                for i=1:nf
                    if ishandle(waithandle)
                        if mod(i, waitbarfps) == 0
                            waitbar(((k-1)*nf+i)/(numberofregionsfound*nf),waithandle);
                        end
                    else
                        break;
                    end
                    fprintf(exportfile, '%d\t', i);
                    
                    foundtheregion = false;
                    for j=1:numberofregions(i)
                        if (strcmp(char(regionname(i,j,:)), char(rationames(k,:))) == 1)
                            fprintf(exportfile, '%f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%f\t%f\t', ratios(i, k), round(leftvalues(i,k)), round(rightvalues(i,k)), round(leftbackground(i,k)), round(rightbackground(i,k)), leftregionx(i,j), rightregionx(i,j), leftregiony(i,j), rightregiony(i,j), leftregionradius(i,j)*radius, rightregionradius(i,j)*radius);
                            if usingbehaviour
                                for l=1:behaviour(i)-1
                                    fprintf(exportfile, '%f\t', NaN);
                                end
                                fprintf(exportfile, '%f\t', ratios(i, k));
                                for l=behaviour(i)+1:7
                                    fprintf(exportfile, '%f\t', NaN);
                                end
                            end
                            foundtheregion = true;
                        end
                    end
                    if ~foundtheregion
%                        disp('did not find');
                        fprintf(exportfile, '%f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%f\t%f\t', NaN(1,11)); %Ensuring that if, for example, there are multiple neurons and no results for the first in a frame, the results for the second go in the appropriate columns by putting NaNs in the first
                        if usingbehaviour
%                            disp('did not find with behaviour');
                            fprintf(exportfile, '%f\t%f\t%f\t%f\t%f\t%f\t%f\t', NaN(1, 7));
                        end
                    end
                    
                    fprintf(exportfile, '\n');
                end
                %}

            fclose(exportfile);
        end
        if ishandle(waithandle)
            close(waithandle);
            fprintf('Exported results as plaintext.\n');
        end
    end

    function returnvalue = bound(value, minvalues, maxvalues)
		if numel(value) > 1
			fprintf(2, 'Error: value argument to function bound must be a scalar.\n');
		end
		realmaxvalue = min(maxvalues(:));
		realminvalue = max(minvalues(:));
		if realmaxvalue < realminvalue
			fprintf(2, 'Error: the smallest upper bound argument passed to function bound is smaller than the largest lower bound.\n');
		end
		tempreturnvalue = value;
		if value > realmaxvalue
			tempreturnvalue = realmaxvalue;
		elseif value < realminvalue
			tempreturnvalue = realminvalue;
		end
		returnvalue = tempreturnvalue;
    end

    function correctedangles = checkangleoverflow(angles)
        correctedangles = angles;
        correctedangles(correctedangles>pi) = correctedangles(correctedangles>pi) - 2*pi;
        correctedangles(correctedangles<-pi) = correctedangles(correctedangles<-pi) + 2*pi;
    end

    function [whichbehaviour, aborting] = manualflagreversal(framefrom, frameuntil)
        
        maxframes = 50;
        
        if frameuntil-framefrom+1 > maxframes
            framestep = (frameuntil-framefrom+1)/maxframes;
        else
            framestep = 1;
        end
        
        aborting = false;
        
        manualflagreversalfigure = figure;
        
        manualreversaltitlepanel = uipanel(manualflagreversalfigure, 'Units','Normalized',...
        'DefaultUicontrolUnits','Normalized','Position',[0.00 0.90 1.00 0.10]);
        
        titletextstring = sprintf('Deciding the direction of movement in frames %d - %d .', framefrom, frameuntil);
        uicontrol(manualreversaltitlepanel,'Style','Text','String',titletextstring,'Position',[0.00 0.00 1.00 1.00]);
        
        displayimages = struct('data', []);
        displayimagecount = 0;
        for i=framefrom:framestep:frameuntil
            displayimagecount = displayimagecount + 1;
            frametoget = round(i);
            if get(handles.channelchooser, 'Value') == 1
                displayimages(displayimagecount).data = LEFT(frametoget);
            elseif get(handles.channelchooser, 'Value') == 2
                displayimages(displayimagecount).data = RIGHT(frametoget);
            end
            %cropping dynamic range to make it easier to see the edges of the worm body
            datamedian = median(displayimages(displayimagecount).data(:));
            lowerbound = datamedian - std(displayimages(displayimagecount).data(:))*1.5;
            upperbound = datamedian + std(displayimages(displayimagecount).data(:))*1.5;
            displayimages(displayimagecount).data(displayimages(displayimagecount).data > upperbound) = upperbound;
            displayimages(displayimagecount).data(displayimages(displayimagecount).data < lowerbound) = lowerbound;
            %end of cropping of the dynamic range to make it easier to see the edges of the worm body
            displayimages(displayimagecount).frame = frametoget;
        end
        
        whichbuttonpressed = CONST_BUTTON_NONE;
        
        manualflagreversalpanel = uipanel(manualflagreversalfigure, 'Units','Normalized', 'DefaultUicontrolUnits','Normalized', 'Position', [0.00 0.00 1.00 0.30]);
        uicontrol(manualflagreversalpanel, 'Style', 'Pushbutton', 'String', 'Forwards', 'Position', [0.00 0.00 0.25 1.00], 'Callback', {@buttonpressed, CONST_BUTTON_FORWARDS});
        uicontrol(manualflagreversalpanel, 'Style', 'Pushbutton', 'String', 'Stationary', 'Position', [0.25 0.00 0.15 1.00], 'Callback', {@buttonpressed, CONST_BUTTON_STATIONARY});
        uicontrol(manualflagreversalpanel, 'Style', 'Pushbutton', 'String', 'Reversal', 'Position', [0.40 0.00 0.25 1.00], 'Callback', {@buttonpressed, CONST_BUTTON_REVERSAL});
        uicontrol(manualflagreversalpanel, 'Style', 'Pushbutton', 'String', 'Invalid', 'Position', [0.65 0.00 0.15 1.00], 'Callback', {@buttonpressed, CONST_BUTTON_INVALID});
        uicontrol(manualflagreversalpanel, 'Style', 'Pushbutton', 'String', 'Abort', 'Position', [0.80 0.00 0.20 1.00], 'Callback', {@buttonpressed, CONST_BUTTON_ABORT});
        
        moviehandle = subplot('Position', [0.00 0.20 1.00 0.65]);
        
        pause on
        currentframehandle = NaN;
        
        currentmovieFPS = max([movieFPS, displayimagecount/moviemaxduration]);
        
        while whichbuttonpressed == CONST_BUTTON_NONE
            
            for i=1:displayimagecount
                earlytime = clock;
                if ishandle(currentframehandle)
                    delete(currentframehandle);
                end
                try
                    currentframehandle = imshow(displayimages(i).data, [], 'parent', moviehandle); colormap(jet);
                    title(moviehandle, sprintf('frame %d', displayimages(i).frame));
                catch, err = lasterror; %#ok<CTCH,LERR>
                    if ~ishandle(moviehandle) %if the movie window was closed (e.g. the user clicked on the x), it's interpreted as an abort command
                        whichbuttonpressed = CONST_BUTTON_ABORT;
                    else
                        rethrow(err);
                    end
                end
                
                drawnow;
                latertime = clock;
                pause(1/currentmovieFPS - etime(latertime, earlytime));
                
                if whichbuttonpressed ~= CONST_BUTTON_NONE
                    break;
                end
            end
            
            if ishandle(currentframehandle)
                delete(currentframehandle);
            end
            drawnow;
            pause(1/currentmovieFPS);
            
            if whichbuttonpressed == CONST_BUTTON_FORWARDS
                whichbehaviour = CONST_BEHAVIOUR_FORWARDS;
            elseif whichbuttonpressed == CONST_BUTTON_STATIONARY
                whichbehaviour = CONST_BEHAVIOUR_STATIONARY;
            elseif whichbuttonpressed == CONST_BUTTON_REVERSAL
                whichbehaviour = CONST_BEHAVIOUR_REVERSAL;
            elseif whichbuttonpressed == CONST_BUTTON_INVALID
                whichbehaviour = CONST_BEHAVIOUR_INVALID;
            elseif whichbuttonpressed == CONST_BUTTON_ABORT
                whichbehaviour = CONST_BEHAVIOUR_INVALID;
                aborting = true;
            end
        
        end
        
        delete(manualflagreversalfigure); %we remove the popup decision figure when we're done
        
    end

    function buttonpressed (hobj, eventdata, whichbutton)  %#ok<INUSL>
       whichbuttonpressed = whichbutton;
       uiresume;
    end

    function detectreversals (hobj, eventdata)  %#ok<INUSD>
        
        %%%%% START OF PARAMETERS %%%%%
        
        %coordinate transformation between stage position and FOV neuron position
        regionxtoactualx = -0.6277; %-0.6289;
        regionytoactualx = -0.0110; %-0.0077;
        regionxtoactualy = -0.0271; %-0.0148;
        regionytoactualy = +0.6427; %+0.6389;
        
        movingsmoothing = [0.3 0.6 1.0 0.6 0.3]; %coordinates are smoothed with this kernel
        
        interpdistancemax = 30; %if there's a hole of more than this many frames between two valid stretches of smoothed coordinates, we won't attempt interpolation for that hole
        datapointspersplinepieces = 10; %number of datapoints that warrant an additional spline piece in the interpolation
        
        stationaryspeedmax = 10; %in um/s
        stationarytimemin = 2; %in s
        
        revdisplacementwindow = 20; %in frames
        
        samedirectionanglemax = 7.5/180*pi; %in degrees being converted into radians
        reversedirectionanglemin = 25/180*pi; %in degrees being converted into radians
        samedirectiontimemin = 90; %in s
        interpolatetimemax = 0.5; %in s. we will not bother asking the user about intervals shorter than this. instead, will try to interpolate, or if that fails just flag it invalid
        
        %%%%% END OF PARAMETERS %%%%%
        
        usingbehaviour = true;
        
        currentregionx = NaN(1, nf);
        currentregiony = NaN(1, nf);
        for i=1:size(regionname, 1)
            for j=1:size(regionname, 2)
                if strcmp(char(regionname(i, j, :)), char(selectedname))
                    currentregionx(i) = rightregionx(i, j);
                    currentregiony(i) = rightregiony(i, j);
                end
            end
        end
        currentregionx(currentregionx == 0) = NaN;
        currentregiony(currentregiony == 0) = NaN;
        
        actualx = framex + regionxtoactualx*currentregionx + regionytoactualx*currentregiony;
        actualy = framey + regionxtoactualy*currentregionx + regionytoactualy*currentregiony;
        
        wherevalid = find(~isnan(actualx) & ~isnan(actualy)); %where data is available for both x and y coordinates
        
        if isempty(wherevalid)
            if strcmp(selectedname, char(ones(1,5)*45))
                errormessage = 'Warning: you must select a region whose position you want to follow before reversals can be detected.';
            elseif isempty(framex) || (numel(framex) == 1 && isnan(framex))
                if strcmp(questdlg('Warning: stage position is unavailable, which makes it impossible to detect reversals properly if the stage moves during the recording.','Stage position unavailable','The stage is stationary throughout the movie, proceed','Cancel','Cancel'),'Cancel')
                	return
                else
                    if numel(framex) == 1 && numel(framey) == 1
                        actualx = currentregionx * framex;
                        actualy = currentregiony * framey;
                    else
                        actualx = currentregionx;
                        actualy = currentregiony;
                    end
                    wherevalid = find(~isnan(actualx) & ~isnan(actualy)); %where data is available for both x and y coordinates
                    %forcing the reentry of frame times, as the user may want to correct the previously entered value
                    frametime = NaN(1, nf);
                    while isnan(frametime(1));
                        usertime = inputdlg('Time between successive frames in the stack (in ms):', 'Enter time interval', 1, {''}, 'on');
                        if isempty(usertime) %user clicked cancel
                            return
                        end
                        timeinterval = str2double(usertime);
                        frametime = 0:timeinterval:(nf-1)*timeinterval;
                    end
                    errormessage = '';
                end
            else
                errormessage = 'Warning: position coordinates were not available. Read in the stage positions, select a neuron of interest, and try again.';
            end
            if ~isempty(errormessage)
                fprintf(2, [errormessage '\n']);
                questdlg(errormessage, 'Reversal detection', 'OK', 'OK');
                return
            end
        end
        
        movingsmoothing = movingsmoothing ./ sum(movingsmoothing); %normalizing
        halfsize = floor(numel(movingsmoothing)/2);
        
        smoothedx = NaN(size(actualx));
        smoothedy = NaN(size(actualy));
        
        for i=1+halfsize:nf-halfsize
            if sum(~isnan(actualx(i-halfsize:i+halfsize))) == numel(movingsmoothing)
                smoothedx(i) = sum(actualx(i-halfsize:i+halfsize).*movingsmoothing);
            end
            if sum(~isnan(actualy(i-halfsize:i+halfsize))) == numel(movingsmoothing)
                smoothedy(i) = sum(actualy(i-halfsize:i+halfsize).*movingsmoothing);
            end
        end
        
        
        goodstarts = strfind(~isnan(smoothedx), [false true])+1; %first index in a string of valid positions
        if ~isnan(smoothedx(1))
            goodstarts = [true goodstarts];
        end
        
        goodends = strfind(~isnan(smoothedx), [true false]); %last index in a string of valid positions
        if ~isnan(smoothedx(end))
            goodends = [goodends numel(smoothedx)+1];
        end
        
        whicharebad = find(isnan(smoothedx));
        
        interpolatedx = smoothedx;
        interpolatedy = smoothedy;
        
        for i=1:numel(goodstarts)-1
            
            if goodends(i)+interpdistancemax < goodstarts(i+1)
                continue;
            end
            interpolatefrom = wherevalid(wherevalid >= goodstarts(i) & wherevalid <= goodends(i+1));
            interpolateinto = whicharebad(whicharebad >= goodstarts(i) & whicharebad <= goodends(i+1));
            
            splinefitx = splinefit(interpolatefrom, actualx(interpolatefrom), ceil(numel(interpolatefrom)/datapointspersplinepieces));
            splinefity = splinefit(interpolatefrom, actualy(interpolatefrom), ceil(numel(interpolatefrom)/datapointspersplinepieces));
            
            interpolatedx(interpolateinto) = ppval(splinefitx, interpolateinto);
            interpolatedy(interpolateinto) = ppval(splinefity, interpolateinto);
            
        end
        
        
        revdisplacementhalfwindow = revdisplacementwindow/2; %frames
        
        dx = [NaN(1, ceil(revdisplacementhalfwindow)) interpolatedx(1+revdisplacementwindow:end)-interpolatedx(1:end-revdisplacementwindow) NaN(1, floor(revdisplacementhalfwindow))];
        dy = [NaN(1, ceil(revdisplacementhalfwindow)) interpolatedy(1+revdisplacementwindow:end)-interpolatedy(1:end-revdisplacementwindow) NaN(1, floor(revdisplacementhalfwindow))];
        
        directions = atan2(dy,dx);
        
        deltaangles = NaN(size(directions));
        deltaangles(2:end) = directions(2:end) - directions(1:end-1);
        %the delta angle between the zeroth and the first directions is assumed to be zero
        deltaangles(find(~isnan(deltaangles), 1)-1) = 0;

        %we always take the smallest angle for each turn so transform angle
        %differences greater than pi to their smaller negative equivalent and
        %values less than -pi to their smaller positive equivalent
        deltaangles = checkangleoverflow(deltaangles);
        
        behaviour(isnan(deltaangles)) = CONST_BEHAVIOUR_INVALID;
        
        if size(frametime, 1) > 1 && size(frametime, 2) == 1
            frametime = frametime';
        end
        
        interpolateddisplacement = [NaN hypot(diff(interpolatedx), diff(interpolatedy))]; %in um
        interpolatedtime = ([NaN, diff(frametime)]/1000); %converting to s from ms
        interpolatedspeed = interpolateddisplacement./interpolatedtime; %in um/s
        
        slowfrom = NaN;
        
        %checking how long the worm can be said to be stationary from the current frame onwards
        fprintf('slow:\n');
        for i=find(behaviour==CONST_BEHAVIOUR_UNKNOWN,1,'first'):find(behaviour==CONST_BEHAVIOUR_UNKNOWN,1,'last')
            if isnan(slowfrom) && behaviour(i) == CONST_BEHAVIOUR_UNKNOWN && interpolatedspeed(i) <= stationaryspeedmax %slow beings
                slowfrom = i;
            end
            if ~isnan(slowfrom) && (behaviour(i) ~= CONST_BEHAVIOUR_UNKNOWN || ~(interpolatedspeed(i) <= stationaryspeedmax)) %slow ends
                if (frametime(i-1)-frametime(slowfrom))/1000 >= stationarytimemin
                    behaviour(slowfrom:i-1) = CONST_BEHAVIOUR_STATIONARY;
                    fprintf('%d to %d\n', slowfrom, i);
                end
                slowfrom = NaN;
            end
        end
        if ~isnan(slowfrom) && (frametime(i-1)-frametime(slowfrom))/1000 >= stationarytimemin
            behaviour(slowfrom:i-1) = CONST_BEHAVIOUR_STATIONARY;
        end
        
        samefrom = NaN;
        samedirections = struct('from', [], 'until', [], 'duration', [], 'status', [], 'left', [], 'right', []);
        samedirectionsnumber = 0;
        
        %extracting samedirection movements
        for i=find(behaviour==CONST_BEHAVIOUR_UNKNOWN,1,'first'):find(behaviour==CONST_BEHAVIOUR_UNKNOWN,1,'last')
            if isnan(samefrom) && behaviour(i) == CONST_BEHAVIOUR_UNKNOWN %same begins
                samefrom = i;
            elseif ~isnan(samefrom) && (behaviour(i) ~= CONST_BEHAVIOUR_UNKNOWN || ~(abs(deltaangles(i)) <= samedirectionanglemax)) %same ends
                samedirectionsnumber = samedirectionsnumber + 1;
                samedirections(samedirectionsnumber).from = samefrom;
                samedirections(samedirectionsnumber).until = i-1;
                samedirections(samedirectionsnumber).duration = (frametime(samedirections(samedirectionsnumber).until)-frametime(samedirections(samedirectionsnumber).from))/1000;
                samedirections(samedirectionsnumber).status = CONST_BEHAVIOUR_UNKNOWN;
                if samedirectionsnumber > 1
                    if samedirections(samedirectionsnumber-1).until+1 == samedirections(samedirectionsnumber).from && deltaangles(samedirections(samedirectionsnumber).from) >= reversedirectionanglemin
                        samedirections(samedirectionsnumber).left = samedirectionsnumber-1;
                        samedirections(samedirectionsnumber-1).right = samedirectionsnumber;
                    else
                        samedirections(samedirectionsnumber).left = NaN;
                        samedirections(samedirectionsnumber-1).right = NaN;
                    end
                else
                    samedirections(samedirectionsnumber).left = NaN;
                end
                samedirections(samedirectionsnumber).right = NaN;
                if behaviour(i) == CONST_BEHAVIOUR_UNKNOWN
                    samefrom = i;
                else
                    samefrom = NaN;
                end
            end
        end
        if ~isnan(samefrom) && i > samefrom
            samedirectionsnumber = samedirectionsnumber + 1;
            samedirections(samedirectionsnumber).from = samefrom;
            samedirections(samedirectionsnumber).until = i-1;
            samedirections(samedirectionsnumber).duration = (frametime(samedirections(samedirectionsnumber).until)-frametime(samedirections(samedirectionsnumber).from))/1000;
            samedirections(samedirectionsnumber).status = CONST_BEHAVIOUR_UNKNOWN;
            
            if samedirectionsnumber > 1
                if samedirections(samedirectionsnumber-1).until+1 == samedirections(samedirectionsnumber).from && deltaangles(samedirections(samedirectionsnumber).from) >= reversedirectionanglemin
                    samedirections(samedirectionsnumber).left = samedirectionsnumber-1;
                    samedirections(samedirectionsnumber-1).right = samedirectionsnumber;
                else
                    samedirections(samedirectionsnumber).left = NaN;
                    samedirections(samedirectionsnumber-1).right = NaN;
                end
            else
                samedirections(samedirectionsnumber).left = NaN;
            end
            samedirections(samedirectionsnumber).right = NaN;
        end
        
        %automatic reversal detection
        aborting = false;
        while ~aborting
            
            longestsamedirwhich = NaN;
            longestsamedir = -Inf;
            for i=1:samedirectionsnumber
                if samedirections(i).status == CONST_BEHAVIOUR_UNKNOWN && samedirections(i).duration > longestsamedir
                    longestsamedirwhich = i;
                    longestsamedir = samedirections(i).duration;
                end
            end
            
            currentsamedir = longestsamedirwhich;
            currentdur = longestsamedir; %in s
            
            if ~isnan(currentsamedir)
            
                leftside = CONST_BEHAVIOUR_UNKNOWN;
                if ~isnan(samedirections(currentsamedir).left)
                    leftside = samedirections(samedirections(currentsamedir).left).status;
                end
                rightside = CONST_BEHAVIOUR_UNKNOWN;
                if ~isnan(samedirections(currentsamedir).right)
                    rightside = samedirections(samedirections(currentsamedir).right).status;
                end
                
                if (leftside == CONST_BEHAVIOUR_UNKNOWN || leftside == CONST_BEHAVIOUR_INVALID || leftside == CONST_BEHAVIOUR_SHORTINTERVAL) && (rightside == CONST_BEHAVIOUR_UNKNOWN || rightside == CONST_BEHAVIOUR_INVALID || rightside == CONST_BEHAVIOUR_SHORTINTERVAL)
                    if currentdur > samedirectiontimemin
                        samedirections(currentsamedir).status = CONST_BEHAVIOUR_FORWARDS;
                    else
                        if samedirections(currentsamedir).duration > interpolatetimemax
                            [currentbehaviour, aborting] = manualflagreversal(samedirections(currentsamedir).from, samedirections(currentsamedir).until);
                            if aborting, break, end
                            samedirections(currentsamedir).status = currentbehaviour;
                        else
                            samedirections(currentsamedir).status = CONST_BEHAVIOUR_SHORTINTERVAL;
                        end
                    end
                elseif (leftside == CONST_BEHAVIOUR_UNKNOWN || leftside == CONST_BEHAVIOUR_INVALID || leftside == CONST_BEHAVIOUR_SHORTINTERVAL || leftside == CONST_BEHAVIOUR_REVERSAL) && (rightside == CONST_BEHAVIOUR_UNKNOWN || rightside == CONST_BEHAVIOUR_INVALID || rightside == CONST_BEHAVIOUR_SHORTINTERVAL || rightside == CONST_BEHAVIOUR_REVERSAL)
                    samedirections(currentsamedir).status = CONST_BEHAVIOUR_FORWARDS;
                elseif (leftside == CONST_BEHAVIOUR_UNKNOWN || leftside == CONST_BEHAVIOUR_INVALID || leftside == CONST_BEHAVIOUR_SHORTINTERVAL || leftside == CONST_BEHAVIOUR_FORWARDS) && (rightside == CONST_BEHAVIOUR_UNKNOWN || rightside == CONST_BEHAVIOUR_INVALID || rightside == CONST_BEHAVIOUR_SHORTINTERVAL || rightside == CONST_BEHAVIOUR_FORWARDS)
                    if currentdur <= samedirectiontimemin 
                        samedirections(currentsamedir).status = CONST_BEHAVIOUR_REVERSAL;
                    else
                        if samedirections(currentsamedir).duration > interpolatetimemax
                            [currentbehaviour, aborting] = manualflagreversal(samedirections(currentsamedir).from, samedirections(currentsamedir).until);
                            if aborting, break, end
                            samedirections(currentsamedir).status = currentbehaviour;
                        else
                            samedirections(currentsamedir).status = CONST_BEHAVIOUR_SHORTINTERVAL;
                        end
                    end
                else
                    if samedirections(currentsamedir).duration > interpolatetimemax
                        [currentbehaviour, aborting] = manualflagreversal(samedirections(currentsamedir).from, samedirections(currentsamedir).until);
                        if aborting, break, end
                        samedirections(currentsamedir).status = currentbehaviour;
                    else
                        samedirections(currentsamedir).status = CONST_BEHAVIOUR_SHORTINTERVAL;
                    end
                end
            else
                break;
            end
            
        end
        
        %flagging the actual behaviour frames
        for i=1:samedirectionsnumber
            if samedirections(i).status ~= CONST_BEHAVIOUR_UNKNOWN && samedirections(i).status ~= CONST_BEHAVIOUR_SHORTINTERVAL
                behaviour(samedirections(i).from:samedirections(i).until) = samedirections(i).status;
            end
        end
        
        %finally, trying to interpolate the short intervals, or flagging them as invalid
        for i=1:samedirectionsnumber
            if samedirections(i).status == CONST_BEHAVIOUR_SHORTINTERVAL
                leftsidesuggests = CONST_BEHAVIOUR_UNKNOWN;
                if samedirections(i).from > 1
                    leftsidesuggests = behaviour(samedirections(i).from-1);
                    leftsideDA = deltaangles(samedirections(i).from-1);
                    if leftsideDA > reversedirectionanglemin %direction change detected, so suggestion is flipped
                        if leftsidesuggests == CONST_BEHAVIOUR_FORWARDS
                            leftsidesuggests = CONST_BEHAVIOUR_REVERSAL;
                        elseif leftsidesuggests == CONST_BEHAVIOUR_REVERSAL
                            leftsidesuggests = CONST_BEHAVIOUR_FORWARDS;
                        end
                    end 
                end                
                
                rightsidesuggests = CONST_BEHAVIOUR_UNKNOWN;
                if samedirections(i).until < nf
                    rightsidesuggests = behaviour(samedirections(i).until+1);
                    rightsideDA = deltaangles(samedirections(i).until+1);
                    if rightsideDA > reversedirectionanglemin %direction change detected, so suggestion is flipped
                        if rightsidesuggests == CONST_BEHAVIOUR_FORWARDS
                            rightsidesuggests = CONST_BEHAVIOUR_REVERSAL;
                        elseif rightsidesuggests == CONST_BEHAVIOUR_REVERSAL
                            rightsidesuggests = CONST_BEHAVIOUR_FORWARDS;
                        end
                    end
                end
                
                if (leftsidesuggests == CONST_BEHAVIOUR_UNKNOWN || leftsidesuggests == CONST_BEHAVIOUR_INVALID || leftsidesuggests == CONST_BEHAVIOUR_STATIONARY) && (rightsidesuggests == CONST_BEHAVIOUR_UNKNOWN || rightsidesuggests == CONST_BEHAVIOUR_INVALID || rightsidesuggests == CONST_BEHAVIOUR_STATIONARY)
                    behaviour(samedirections(i).from:samedirections(i).until) = CONST_BEHAVIOUR_INVALID;
                elseif (leftsidesuggests == CONST_BEHAVIOUR_FORWARDS || leftsidesuggests == CONST_BEHAVIOUR_UNKNOWN || leftsidesuggests == CONST_BEHAVIOUR_INVALID || leftsidesuggests == CONST_BEHAVIOUR_STATIONARY) && (rightsidesuggests == CONST_BEHAVIOUR_FORWARDS || rightsidesuggests == CONST_BEHAVIOUR_UNKNOWN || rightsidesuggests == CONST_BEHAVIOUR_INVALID || rightsidesuggests == CONST_BEHAVIOUR_STATIONARY)
                    behaviour(samedirections(i).from:samedirections(i).until) = CONST_BEHAVIOUR_FORWARDS;
                elseif (leftsidesuggests == CONST_BEHAVIOUR_REVERSAL || leftsidesuggests == CONST_BEHAVIOUR_UNKNOWN || leftsidesuggests == CONST_BEHAVIOUR_INVALID || leftsidesuggests == CONST_BEHAVIOUR_STATIONARY) && (rightsidesuggests == CONST_BEHAVIOUR_REVERSAL || rightsidesuggests == CONST_BEHAVIOUR_UNKNOWN || rightsidesuggests == CONST_BEHAVIOUR_INVALID || rightsidesuggests == CONST_BEHAVIOUR_STATIONARY)
                    behaviour(samedirections(i).from:samedirections(i).until) = CONST_BEHAVIOUR_REVERSAL;
                elseif leftsidesuggests == CONST_BEHAVIOUR_FORWARDS && rightsidesuggests == CONST_BEHAVIOUR_REVERSAL
                    middlepoint = samedirections(i).from+floor((samedirections(i).until-samedirections(i).from)/2);
                    behaviour(samedirections(i).from:middlepoint) = CONST_BEHAVIOUR_FORWARDS;
                    behaviour(middlepoint+1:samedirections(i).until) = CONST_BEHAVIOUR_REVERSAL;
                elseif leftsidesuggests == CONST_BEHAVIOUR_REVERSAL && rightsidesuggests == CONST_BEHAVIOUR_FORWARDS
                    middlepoint = samedirections(i).from+floor((samedirections(i).until-samedirections(i).from)/2);
                    behaviour(samedirections(i).from:middlepoint) = CONST_BEHAVIOUR_REVERSAL;
                    behaviour(middlepoint+1:samedirections(i).until) = CONST_BEHAVIOUR_FORWARDS;
                else
                    error('Could not decide what to do when trying to interpolate a short interval.\n');
                end
            end
        end
        
        if ~aborting
            questdlg('Reversal detection completed successfully.', 'Reversal detection completed', 'OK', 'OK');
        end       
        
    end
    
    function howmany = number (astructmaybe)
        howmany = numel(astructmaybe);
        if howmany == 1 && isstruct(astructmaybe)
            fields = fieldnames(astructmaybe);
            allempty = true;
            for i=1:numel(fields)
                currentfieldvalue = astructmaybe(end).(fields{i});
                if isstruct(currentfieldvalue) || (~isempty(currentfieldvalue) && ~all(isnan(currentfieldvalue)))
                    allempty = false;
                    break;
                end
            end
            if allempty
                howmany = 0;
            end
        end
    end


    function setvalue (hobj, eventdata, varargin) %#ok<INUSL>
        %parsing input arguments
        inputindex=1;
        while (inputindex<=numel(varargin))
            if strcmpi(varargin{inputindex}, 'min') == 1 || strcmpi(varargin{inputindex}, 'minvalue') == 1
                minvalue = varargin{inputindex+1};
                if ischar(minvalue)
                    minvalue = eval(minvalue);
                end
                inputindex=inputindex+2;
            elseif strcmpi(varargin{inputindex}, 'max') == 1 || strcmpi(varargin{inputindex}, 'maxvalue') == 1
                maxvalue = varargin{inputindex+1};
                if ischar(maxvalue)
                    maxvalue = eval(maxvalue);
                end
                inputindex=inputindex+2;
            elseif strcmpi(varargin{inputindex}, 'round') == 1 || strcmpi(varargin{inputindex}, 'rounding') == 1
                rounding = varargin{inputindex+1};
                if ischar(rounding)
                    rounding = eval(rounding);
                end
                inputindex=inputindex+2;
            elseif strcmpi(varargin{inputindex}, 'default') == 1
                default = varargin{inputindex+1};
                inputindex=inputindex+2;
            elseif strcmpi(varargin{inputindex}, 'set') == 1 || strcmpi(varargin{inputindex}, 'setglobal') == 1
                setglobal = varargin{inputindex+1};
                inputindex=inputindex+2;
            elseif strcmpi(varargin{inputindex}, 'logical') == 1 || strcmpi(varargin{inputindex}, 'logic') == 1
                logic = true;
                inputindex=inputindex+1;
            elseif strcmpi(varargin{inputindex}, 'show') == 1 || strcmpi(varargin{inputindex}, 'showit') == 1
                showit = true;
                inputindex=inputindex+1;
            end
        end
        
        if exist('default', 'var') ~= 1
            default = '-';
        end
        if exist('logic', 'var') ~= 1
            logic = false;
        end
        if exist('showit', 'var') ~= 1
            showit = false;
        end
        
        if ~logic
            tempnumber = str2double(get(hobj, 'String'));
        else
            tempnumber = get(hobj, 'Value');
        end
        
        if exist('rounding', 'var') == 1
            tempnumber = round(tempnumber * rounding)/rounding;
        end
        if exist('minvalue', 'var') == 1 && tempnumber < minvalue
            tempnumber = minvalue;
        end
        if exist('maxvalue', 'var') == 1 && tempnumber > maxvalue
            tempnumber = maxvalue;
        end
        
        if ~logic
            if ~isnan(tempnumber)
                set(hobj, 'String', num2str(tempnumber))
            else
                set(hobj, 'String', default);
            end
        end
        
        if exist('setglobal', 'var') == 1
            if isnan(tempnumber) && strcmpi(class(default), 'double')
                eval([setglobal '= default;']);
            else
                eval([setglobal '= tempnumber;']);
            end
        end
        
        if showit
            showframe;
        end
    end

    function debuggingfunction (hobj, eventdata) %#ok<INUSD>
                
        disp(' ');
        disp('start');
        
        keyboard;
                
        disp('end');
        disp(' ');
        
    end

end