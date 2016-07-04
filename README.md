# Usage
xfs format -file-name &lt;name&gt; -size &lt;size&gt; -block-size &lt;size&gt; -descriptors-count &lt;count&gt;<br/>
xfs mount -file-name &lt;name&gt;<br/>
xfs umount<br/>
xfs filestat -file-name &lt;name&gt;<br/>
xfs list<br/>
xfs create -file-name &lt;name&gt;<br/>
xfs open -file-name &lt;name&gt;<br/>
xfs close -fd &lt;fd&gt;<br/>
xfs close-all<br/>
xfs read -fd &lt;fd&gt; [-offset &lt;offset&gt;] -size &lt;size&gt;<br/>
xfs read -fd &lt;fd&gt; [-offset &lt;offset&gt;]<br/>
xfs link -file-name &lt;name&gt; -link-name &lt;name&gt;<br/>
xfs unlink -link-name &lt;name&gt;<br/>
xfs truncate format -file-name &lt;name&gt; -size &lt;size&gt;<br/>
xfs info<br/>
xfs version<br/>
